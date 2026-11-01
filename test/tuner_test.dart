import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/features/tuner/audio_input.dart';
import 'package:riffshelf/features/tuner/pitch_detector.dart';
import 'package:riffshelf/screens/tuner_screen.dart';

class FakeInput implements TunerAudioInput {
  FakeInput(this.status);
  final MicrophoneStatus status;
  final controller = StreamController<Uint8List>();

  @override
  int get sampleRate => 22050;
  @override
  Future<MicrophoneStatus> prepare() async => status;
  @override
  Future<Stream<Uint8List>> start() async => controller.stream;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

Float64List sine(double hz, int n, int rate) => Float64List.fromList([
  for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * hz * i / rate),
]);

Uint8List pcm(Float64List samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, (samples[i] * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('PitchDetector', () {
    test('detects guitar and bass pitches', () {
      final detector = PitchDetector(sampleRate: 22050);
      for (final hz in [41.2, 82.41, 110.0, 196.0, 329.63]) {
        final result = detector.detect(sine(hz, detector.windowSize, 22050));
        expect(result, isNotNull, reason: '$hz');
        expect(result!.frequency, closeTo(hz, hz * 0.01), reason: '$hz');
      }
    });

    test('ignores silence', () {
      final detector = PitchDetector(sampleRate: 22050);
      expect(detector.detect(Float64List(detector.windowSize)), isNull);
    });

    test('maps frequencies to notes', () {
      final note = nearestNote(82.41);
      expect(note.label, 'E2');
      expect(note.cents.abs(), lessThan(1));
      expect(midiFromNoteName('A4'), 69);
    });
  });

  group('TunerScreen', () {
    Future<void> pumpTuner(WidgetTester tester, FakeInput input) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TunerScreen(inputFactory: () => input)),
        ),
      );
    }

    testWidgets('explains when there is no microphone', (tester) async {
      await pumpTuner(tester, FakeInput(MicrophoneStatus.noMicrophone));
      await tester.tap(find.text('Start tuning'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No microphone was found'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('explains when permission is denied', (tester) async {
      await pumpTuner(tester, FakeInput(MicrophoneStatus.permissionDenied));
      await tester.tap(find.text('Start tuning'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Microphone access is turned off'),
        findsOneWidget,
      );
    });

    testWidgets('shows the detected string', (tester) async {
      final input = FakeInput(MicrophoneStatus.available);
      await pumpTuner(tester, input);
      await tester.tap(find.text('Start tuning'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Stop'), findsOneWidget);

      final samples = sine(110.0, 22050, 22050);
      input.controller.add(pcm(samples));
      await tester.pump(const Duration(milliseconds: 10));

      expect(
        tester.widget<Text>(find.byKey(const Key('tuner-target-note'))).data,
        'A2',
      );
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
    });
  });
}
