import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

enum MicrophoneStatus { available, permissionDenied, noMicrophone, error }

/// Source of mono PCM audio. Abstracted so the tuner can be tested without
/// real hardware.
abstract class TunerAudioInput {
  int get sampleRate;

  /// Checks for an input device and (if needed) asks for permission.
  Future<MicrophoneStatus> prepare();

  /// Streams signed 16-bit little-endian mono PCM chunks.
  Future<Stream<Uint8List>> start();

  Future<void> stop();

  Future<void> dispose();
}

class RecordAudioInput implements TunerAudioInput {
  RecordAudioInput({AudioRecorder? recorder}) : _injected = recorder;

  final AudioRecorder? _injected;

  // Created lazily so merely showing the tuner never touches the plugin.
  late final AudioRecorder _recorder = _injected ?? AudioRecorder();

  @override
  final int sampleRate = 22050;

  @override
  Future<MicrophoneStatus> prepare() async {
    try {
      if (!await _recorder.hasPermission()) {
        return MicrophoneStatus.permissionDenied;
      }
      try {
        final devices = await _recorder.listInputDevices();
        if (devices.isEmpty) return MicrophoneStatus.noMicrophone;
      } catch (_) {
        // Some platforms can't enumerate devices; starting will reveal it.
      }
      return MicrophoneStatus.available;
    } catch (_) {
      return MicrophoneStatus.error;
    }
  }

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
    RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    ),
  );

  @override
  Future<void> stop() async {
    if (await _recorder.isRecording()) await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
