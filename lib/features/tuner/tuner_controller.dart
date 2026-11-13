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
    this.onPitch,
    this._preset = TunerPresets.guitarStandard,
  }) : _input = input,
       _detector = PitchDetector(sampleRate: input.sampleRate) {
    _window = Float64List(_detector.windowSize);
  }

  static const _analysisInterval = Duration(milliseconds: 80);
  static const _minimumConfidence = 0.85;
  static const _stableCents = 45.0;

  /// When supplied, emit each detector observation instead of tuner readings.
  final ValueChanged<PitchResult?>? onPitch;

  // Both tuner routes and practice use this queue. An acquisition cannot
  // overtake an in-flight stop, disposal, or cancelled startup.
  static Future<void>? _captureQueue;
  static TunerController? _captureOwner;

  static Future<void> _serialize(Future<void> Function() action) {
    final previous = _captureQueue;
    final operation = previous == null
        ? Future<void>.microtask(action)
        : previous.then((_) => action());
    late final Future<void> tail;
    tail = operation.catchError((Object _) {}).whenComplete(() {
      if (identical(_captureQueue, tail)) _captureQueue = null;
    });
    _captureQueue = tail;
    return operation;
  }

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
  bool _inputUsed = false;
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

  Future<void> start() {
    if (_disposed ||
        _status == TunerStatus.starting ||
        _status == TunerStatus.listening) {
      return Future<void>.value();
    }
    final session = ++_session;
    _setStatus(TunerStatus.starting);
    return _serialize(() async {
      if (_cancelled(session)) return;
      try {
        final previous = _captureOwner;
        if (previous != null && previous != this) {
          final previousSession = ++previous._session;
          await previous._release();
          if (!previous._cancelled(previousSession)) {
            previous._setStatus(TunerStatus.idle);
          }
        }
        if (_cancelled(session)) return;
        _inputUsed = true;
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
        _captureOwner = this;
        final stream = await _input.start();
        if (_cancelled(session)) {
          await _release();
          return;
        }
        _filled = 0;
        _sinceAnalysis = 0;
        _carryByte = null;
        _window.fillRange(0, _window.length, 0);
        _resetCandidate();
        _subscription = stream.listen(
          (bytes) {
            if (!_cancelled(session)) _onAudio(bytes);
          },
          onError: (Object _) => _fail(session),
          onDone: () => _fail(session),
          cancelOnError: true,
        );
        _setStatus(TunerStatus.listening);
      } catch (_) {
        try {
          await _release();
        } catch (_) {
          // Retain ownership on a failed stop; the next acquire must retry it.
        }
        if (!_cancelled(session)) _setStatus(TunerStatus.error);
      }
    });
  }

  Future<void> stop() {
    if (_disposed) return Future<void>.value();
    final session = ++_session;
    _reading = null;
    if (_status != TunerStatus.idle) _setStatus(TunerStatus.idle);
    return _serialize(() async {
      try {
        await _release();
        if (!_cancelled(session) && _status != TunerStatus.idle) {
          _setStatus(TunerStatus.idle);
        }
      } catch (_) {
        if (!_cancelled(session)) _setStatus(TunerStatus.error);
      }
    });
  }

  bool _cancelled(int session) => _disposed || session != _session;

  void _fail(int session) {
    if (_cancelled(session)) return;
    final failedSession = ++_session;
    _serialize(() async {
      try {
        await _release();
      } catch (_) {
        // A later acquisition must retry a failed release.
      }
      if (!_cancelled(failedSession)) _setStatus(TunerStatus.error);
    });
  }

  Future<void> _release() async {
    _reading = null;
    _resetCandidate();
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    if (_captureOwner == this) {
      await _input.stop();
      _captureOwner = null;
    }
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
    if (onPitch case final callback?) {
      callback(pitch);
      return;
    }
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
    // An unopened input has nothing to release. In particular, don't
    // initialize a native recorder just to dispose it on route teardown.
    if (_inputUsed) {
      _serialize(() async {
        try {
          await _release();
        } finally {
          await _input.dispose();
          if (_captureOwner == this) _captureOwner = null;
        }
      }).catchError((Object _) {});
    }
    super.dispose();
  }
}
