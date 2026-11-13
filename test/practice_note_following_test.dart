import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/practice_session_screen.dart';
import 'package:riffshelf/features/tuner/audio_input.dart';
import 'package:riffshelf/features/tuner/tuner_controller.dart';

class FakeAudio implements TunerAudioInput {
  FakeAudio([this.availability = MicrophoneStatus.available]);
  final MicrophoneStatus availability;
  StreamController<Uint8List> frames = StreamController<Uint8List>(
    onCancel: () async {},
  );
  Future<void>? stopGate;
  Future<void>? startGate;
  int starts = 0;
  int stops = 0;
  int disposals = 0;
  @override
  int get sampleRate => 22050;
  @override
  Future<MicrophoneStatus> prepare() async => availability;
  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    await startGate;
    frames = StreamController<Uint8List>(onCancel: () async {});
    return frames.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopGate;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    unawaited(frames.close());
  }

  void emit(double frequency) {
    final samples = ByteData(3600);
    for (var i = 0; i < 1800; i++) {
      samples.setInt16(
        i * 2,
        (12000 * math.sin(2 * math.pi * frequency * i / sampleRate)).round(),
        Endian.little,
      );
    }
    if (frames.hasListener) frames.add(samples.buffer.asUint8List());
  }
}

SavedTab tab({bool chord = false, bool approximate = false}) => SavedTab(
  title: 'Following fixture',
  artist: '',
  source: 'test',
  sourceUrl: '',
  instrument: InstrumentType.guitar,
  stringCount: 6,
  tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
  measures: [
    TabMeasure(
      number: 1,
      numerator: approximate ? 0 : 4,
      beats: [
        TabBeat(
          position: 0,
          notes: [
            const TabNote(stringNumber: 1, fret: 5, midiPitch: 69),
            if (chord) const TabNote(stringNumber: 2, fret: 5, midiPitch: 64),
          ],
        ),
      ],
    ),
    const TabMeasure(
      number: 2,
      beats: [
        TabBeat(
          position: 0,
          notes: [TabNote(stringNumber: 1, fret: 7, midiPitch: 71)],
        ),
      ],
    ),
  ],
);

final play = find.byKey(const ValueKey('practice-play-pause'));
final status = find.byKey(const ValueKey('practice-follow-status'));

Future<void> showPractice(
  WidgetTester tester,
  FakeAudio audio, {
  bool chord = false,
  bool approximate = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PracticeSessionScreen(
        tab: tab(chord: chord, approximate: approximate),
        inputFactory: () => audio,
      ),
    ),
  );
  await tester.pump();
}

Future<void> tapPlay(WidgetTester tester) async {
  await tester.ensureVisible(play);
  await tester.pump();
  await tester.tap(play);
  await tester.pump();
  await tester.pump();
}

Future<void> frames(
  WidgetTester tester,
  FakeAudio audio,
  double hz,
  int count,
) async {
  for (var i = 0; i < count; i++) {
    audio.emit(hz);
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  testWidgets('visible note-by-note mode matches pitches on approximate tabs', (
    tester,
  ) async {
    final audio = FakeAudio();
    await showPractice(tester, audio, approximate: true);
    await tester.tap(find.text('Note by note'));
    await tester.pump();
    await tapPlay(tester);
    expect(find.textContaining('Play A4 (string 1, fret 5)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await frames(tester, audio, 880, 3);
    expect(find.text('Measure 1 of 2'), findsOneWidget);
    await frames(tester, audio, 440, 3);
    expect(find.text('Measure 2 of 2'), findsOneWidget);
    expect(find.textContaining('Play B4 (string 1, fret 7)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'timed practice stays default; following waits for real pitch observations',
    (tester) async {
      final audio = FakeAudio();
      await showPractice(tester, audio);
      await tapPlay(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Measure 2 of 2'), findsOneWidget);
      expect(audio.starts, 0);
      await tester.tap(find.byTooltip('Note Following'));
      await tester.pump();
      final restart = find.byTooltip('Restart');
      await tester.ensureVisible(restart);
      await tester.tap(restart);
      await tester.pump();
      await tapPlay(tester);
      expect(find.textContaining('Listening'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await frames(tester, audio, 0, 4);
      await frames(tester, audio, 880, 4);
      expect(find.text('Measure 1 of 2'), findsOneWidget);
      await frames(tester, audio, 440, 2);
      expect(find.text('Measure 1 of 2'), findsOneWidget);
      await frames(tester, audio, 440, 1);
      expect(
        find.text('Measure 2 of 2'),
        findsOneWidget,
        reason: tester.widget<Text>(status).data,
      );
      expect(find.textContaining('Recognized A4'), findsOneWidget);
      await frames(tester, audio, 493.883, 3);
      expect(find.textContaining('Section complete.'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(audio.stops, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(audio.disposals, 1);
    },
  );

  testWidgets(
    'pause, restart, seek and section edits invalidate pending evidence',
    (tester) async {
      final audio = FakeAudio();
      await showPractice(tester, audio);
      await tester.tap(find.byTooltip('Note Following'));
      await tester.pump();
      await tapPlay(tester);
      await frames(tester, audio, 440, 2);
      await tapPlay(tester);
      await frames(tester, audio, 440, 3);
      expect(find.text('Measure 1 of 2'), findsOneWidget);
      await tapPlay(tester);
      await frames(tester, audio, 440, 1);
      expect(find.text('Measure 1 of 2'), findsOneWidget);
      final restart = find.byTooltip('Restart');
      await tester.ensureVisible(restart);
      await tester.tap(restart);
      await tester.pump();
      await frames(tester, audio, 440, 3);
      expect(find.text('Measure 1 of 2'), findsOneWidget);
      await tapPlay(tester);
      final section = tester.widget<RangeSlider>(find.byType(RangeSlider));
      section.onChanged!(const RangeValues(1, 1));
      await tester.pump();
      await frames(tester, audio, 493.883, 3);
      expect(find.textContaining('Press Play to listen'), findsOneWidget);
      expect(find.textContaining('Recognized'), findsNothing);
      expect(find.text('Measure 2 of 2'), findsOneWidget);
      await tapPlay(tester);
      final track = find.byKey(const ValueKey('practice-track'));
      await tester.ensureVisible(track);
      await tester.drag(track, const Offset(100, 0));
      await tester.pump();
      await frames(tester, audio, 493.883, 3);
      expect(find.textContaining('Recognized'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('chords are skipped; timeout and background stop listening', (
    tester,
  ) async {
    final audio = FakeAudio();
    await showPractice(tester, audio, chord: true);
    await tester.tap(find.byTooltip('Note Following'));
    await tester.pump();
    expect(find.text('Measure 2 of 2'), findsOneWidget);
    expect(
      find.textContaining('1 unsupported passages skipped'),
      findsOneWidget,
    );
    await tapPlay(tester);
    await frames(tester, audio, 440, 4);
    expect(find.textContaining('Recognized'), findsNothing);
    await tester.pump(const Duration(seconds: 20));
    expect(find.textContaining('No matching note heard'), findsOneWidget);
    expect(audio.stops, 1);
    await tapPlay(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(audio.stops, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.textContaining('Press Play to listen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final (availability, message) in [
    (MicrophoneStatus.permissionDenied, 'Microphone access denied'),
    (MicrophoneStatus.noMicrophone, 'No microphone is available'),
    (MicrophoneStatus.error, 'Microphone capture failed'),
  ]) {
    testWidgets('shows $availability without advancing', (tester) async {
      final audio = FakeAudio(availability);
      await showPractice(tester, audio);
      await tester.tap(find.byTooltip('Note Following'));
      await tester.pump();
      await tapPlay(tester);
      expect(find.textContaining(message), findsOneWidget);
      expect(audio.starts, 0);
      expect(find.text('Measure 1 of 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('mode switch cancels in-flight microphone startup', (
    tester,
  ) async {
    final gate = Completer<void>();
    final audio = FakeAudio()..startGate = gate.future;
    await showPractice(tester, audio);
    await tester.tap(find.byTooltip('Note Following'));
    await tester.pump();
    await tapPlay(tester);
    expect(audio.starts, 1);
    await tester.tap(find.byTooltip('Note Following'));
    await tester.pump();
    gate.complete();
    await tester.pump();
    expect(audio.stops, 1);
    expect(status, findsNothing);
    await frames(tester, audio, 440, 3);
    expect(find.text('Measure 1 of 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('practice waits for tuner release and reports capture errors', (
    tester,
  ) async {
    final release = Completer<void>();
    final tunerAudio = FakeAudio()..stopGate = release.future;
    final tuner = TunerController(input: tunerAudio);
    unawaited(tuner.start());
    await tester.pump();
    expect(tuner.isListening, isTrue);

    final audio = FakeAudio();
    await showPractice(tester, audio);
    await tester.tap(find.byTooltip('Note Following'));
    await tester.pump();
    await tapPlay(tester);
    expect(tunerAudio.stops, 1);
    expect(audio.starts, 0);
    release.complete();
    await tester.pump();
    expect(tuner.status, TunerStatus.idle);
    expect(audio.starts, 1);
    audio.frames.addError(StateError('capture failed'));
    await tester.pump();
    expect(find.textContaining('Microphone capture failed'), findsOneWidget);
    expect(audio.stops, 1);
    tuner.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
