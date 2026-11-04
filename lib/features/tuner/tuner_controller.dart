import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/tuning.dart';
import 'audio_input.dart';
import 'pitch_detector.dart';

enum TunerStatus {
  idle,
  starting,
  listening,
  permissionDenied,
  noMicrophone,
  error,
}

@immutable
class TunerReading {
  const TunerReading({
    required this.frequency,
    required this.note,
    required this.targetNote,
    required this.targetCents,
  });

  final double frequency;

  /// Chromatic note nearest to the detected pitch.
  final NoteMatch note;

  /// The selected preset string, or the closest one in automatic mode.
  final String targetNote;

  /// Cents offset from [targetNote]; positive means sharp.
  final double targetCents;

  bool get inTune => targetCents.abs() <= 5;
}

class TunerController extends ChangeNotifier {
  TunerController({
    required TunerAudioInput input,
    this._preset = TunerPresets.guitarStandard,
  }) : _input = input,
       _detector = PitchDetector(sampleRate: input.sampleRate) {
    _window = Float64List(_detector.windowSize);
  }

  static const _analysisInterval = Duration(milliseconds: 80);
  static const _minimumConfidence = 0.85;
  static const _stableCents = 45.0;

  final TunerAudioInput _input;
  final PitchDetector _detector;
  late final Float64List _window;
  TuningPreset _preset;
  TunerStatus _status = TunerStatus.idle;
  TunerReading? _reading;
  StreamSubscription<Uint8List>? _subscription;
  int _filled = 0;
  int _sinceAnalysis = 0;
  int _session = 0;
  bool _disposed = false;
  double? _candidateFrequency;
  int _candidateFrames = 0;
  int? _selectedStringIndex;
  int? _carryByte;

  TunerStatus get status => _status;
  TunerReading? get reading => _reading;
  TuningPreset get preset => _preset;
  int? get selectedStringIndex => _selectedStringIndex;
  bool get isListening => _status == TunerStatus.listening;

  void selectString(int? index) {
    if (index != null && (index < 0 || index >= _preset.notes.length)) {
      throw RangeError.index(index, _preset.notes);
    }
    if (_selectedStringIndex == index) return;
    _selectedStringIndex = index;
    _reading = null;
    _resetCandidate();
    _notify();
  }

  set preset(TuningPreset value) {
    if (identical(value, _preset)) return;
    _preset = value;
    _selectedStringIndex = null;
    _reading = null;
    _resetCandidate();
    _notify();
  }

  Future<void> start() async {
    if (_status == TunerStatus.starting || _status == TunerStatus.listening) {
      return;
    }
    final session = ++_session;
    _setStatus(TunerStatus.starting);

    final availability = await _input.prepare();
    if (_cancelled(session)) return;
    switch (availability) {
      case MicrophoneStatus.permissionDenied:
        return _setStatus(TunerStatus.permissionDenied);
      case MicrophoneStatus.noMicrophone:
        return _setStatus(TunerStatus.noMicrophone);
      case MicrophoneStatus.error:
        return _setStatus(TunerStatus.error);
      case MicrophoneStatus.available:
        break;
    }

    try {
      final stream = await _input.start();
      if (_cancelled(session)) {
        await _input.stop();
        return;
      }
      _filled = 0;
      _sinceAnalysis = 0;
      _carryByte = null;
      _window.fillRange(0, _window.length, 0);
      _resetCandidate();
      _subscription = stream.listen(
        _onAudio,
        onError: (_) => _fail(session),
        onDone: () => _fail(session),
        cancelOnError: true,
      );
      _setStatus(TunerStatus.listening);
    } catch (_) {
      if (_cancelled(session)) return;
      // Starting after a successful check usually means the device vanished.
      _setStatus(TunerStatus.noMicrophone);
    }
  }

  Future<void> stop() async {
    _session++;
    await _teardown();
    if (_status != TunerStatus.idle) _setStatus(TunerStatus.idle);
  }

  bool _cancelled(int session) => _disposed || session != _session;

  void _fail(int session) {
    if (_cancelled(session)) return;
    _session++;
    _teardown();
    _setStatus(TunerStatus.noMicrophone);
  }

  Future<void> _teardown() async {
    _reading = null;
    _resetCandidate();
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    try {
      await _input.stop();
    } catch (_) {}
  }

  void _onAudio(Uint8List bytes) {
    var data = bytes;
    if (_carryByte != null) {
      data = Uint8List(bytes.length + 1)
        ..[0] = _carryByte!
        ..setRange(1, bytes.length + 1, bytes);
      _carryByte = null;
    }
    if (data.length.isOdd) {
      _carryByte = data.last;
      data = Uint8List.sublistView(data, 0, data.length - 1);
    }
    final view = ByteData.sublistView(data);
    final count = data.length ~/ 2;
    if (count == 0) return;

    final size = _window.length;
    final take = count > size ? size : count;
    final offset = count - take;
    _window.setRange(0, size - take, _window, take);
    for (var i = 0; i < take; i++) {
      _window[size - take + i] =
          view.getInt16((offset + i) * 2, Endian.little) / 32768.0;
    }
    _filled = (_filled + take).clamp(0, size);
    _sinceAnalysis += count;

    final interval =
        _input.sampleRate * _analysisInterval.inMilliseconds ~/ 1000;
    if (_filled < size || _sinceAnalysis < interval) return;
    _sinceAnalysis = 0;
    _analyze();
  }

  void _analyze() {
    final pitch = _detector.detect(_window);
    if (pitch == null ||
        !pitch.frequency.isFinite ||
        pitch.confidence < _minimumConfidence) {
      _resetCandidate();
      _clearReading();
      return;
    }

    if (_candidateFrequency == null ||
        centsBetween(pitch.frequency, _candidateFrequency!).abs() >
            _stableCents) {
      _candidateFrequency = pitch.frequency;
      _candidateFrames = 1;
      _clearReading();
      return;
    }
    _candidateFrequency = pitch.frequency;
    _candidateFrames++;
    if (_candidateFrames < 2) return;

    String? bestNote = _selectedStringIndex == null
        ? null
        : _preset.notes[_selectedStringIndex!];
    double bestCents = double.infinity;
    for (final name in bestNote == null ? _preset.notes : [bestNote]) {
      final midi = midiFromNoteName(name);
      if (midi == null) continue;
      final cents = centsBetween(pitch.frequency, frequencyFromMidi(midi));
      if (cents.abs() < bestCents.abs()) {
        bestCents = cents;
        bestNote = name;
      }
    }
    if (bestNote == null) return;

    _reading = TunerReading(
      frequency: pitch.frequency,
      note: nearestNote(pitch.frequency),
      targetNote: bestNote,
      targetCents: bestCents,
    );
    _notify();
  }

  void _resetCandidate() {
    _candidateFrequency = null;
    _candidateFrames = 0;
  }

  void _clearReading() {
    if (_reading == null) return;
    _reading = null;
    _notify();
  }

  void _setStatus(TunerStatus status) {
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    final subscription = _subscription;
    _subscription = null;
    subscription?.cancel();
    _input.stop().whenComplete(_input.dispose).catchError((_) {});
    super.dispose();
  }
}
