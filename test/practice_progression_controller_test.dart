import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/note_matcher.dart';
import 'package:riffshelf/features/tabs/practice_progression_controller.dart';
import 'package:riffshelf/features/tabs/practice_timeline.dart';
import 'package:riffshelf/features/tuner/pitch_detector.dart';

TabNote note(
  int? midi, {
  int string = 1,
  double? duration,
  String? technique,
}) => TabNote(
  stringNumber: string,
  fret: 0,
  midiPitch: midi,
  duration: duration,
  technique: technique,
);
PracticeTimeline timeline(List<TabBeat> beats) => PracticeTimeline.fromTab(
  SavedTab(
    title: 'Fixture',
    artist: '',
    source: '',
    sourceUrl: '',
    instrument: InstrumentType.guitar,
    stringCount: 6,
    tuning: const ['?', '?', '?', '?', '?', '?'],
    measures: [TabMeasure(number: 1, numerator: 8, beats: beats)],
  ),
);
PitchResult pitch(int midi) => PitchResult(frequencyFromMidi(midi), .99);
PracticeProgressionResult play(
  PracticeProgressionController controller,
  int midi,
) {
  controller.observe(pitch(midi));
  controller.observe(pitch(midi));
  return controller.observe(pitch(midi));
}

void main() {
  test(
    'waits for confirmed notes in chronological order, using beat positions',
    () {
      final controller = PracticeProgressionController(
        timeline([
          TabBeat(position: 4, notes: [note(72)]),
          TabBeat(position: 0, notes: [note(69)]),
          TabBeat(position: 2, notes: [note(71)]),
        ]),
      );
      expect(controller.positionBeats, 0);
      expect(
        controller.observe(pitch(70)).match!.status,
        NoteMatchStatus.notMatched,
      );
      expect(controller.observe(null).matchedEvent, isNull);
      controller.observe(pitch(69));
      controller.observe(pitch(69));
      expect(controller.positionBeats, 0);
      final result = controller.observe(pitch(69));
      expect(result.matchedEvent!.expectedMidiPitch, 69);
      expect(result.positionBeats, 2);
      play(controller, 71);
      expect(controller.positionBeats, 4);
      expect(play(controller, 72).completed, isTrue);
      expect(controller.positionBeats, 8);
      expect(controller.observe(pitch(72)).matchedEvent, isNull);
    },
  );

  test('sustain cannot consume repeated notes; silence rearms them', () {
    final controller = PracticeProgressionController(
      timeline([
        TabBeat(position: 0, notes: [note(69)]),
        TabBeat(position: 2, notes: [note(69)]),
      ]),
    );
    play(controller, 69);
    for (var i = 0; i < 10; i++) {
      expect(controller.observe(pitch(69)).matchedEvent, isNull);
    }
    expect(controller.positionBeats, 2);
    controller.observe(null);
    controller.observe(null);
    expect(play(controller, 69).completed, isTrue);
  });

  test(
    'chords including unisons are skipped and never credited by one pitch',
    () {
      final controller = PracticeProgressionController(
        timeline([
          TabBeat(position: 0, notes: [note(69), note(69, string: 2)]),
          TabBeat(position: 2, notes: [note(72)]),
        ]),
      );
      expect(
        controller.skippedPassages.single.reason,
        UnsupportedPassageReason.chord,
      );
      expect(controller.positionBeats, 2);
      expect(play(controller, 69).matchedEvent, isNull);
      expect(play(controller, 72).matchedEvent!.startBeat, 2);
    },
  );

  test(
    'rests, gaps and missing pitches are skipped without fabricating matches',
    () {
      final controller = PracticeProgressionController(
        timeline([
          const TabBeat(position: 0, isRest: true),
          TabBeat(position: 2, notes: [note(null)]),
          TabBeat(position: 5, notes: [note(69)]),
        ]),
      );
      expect(controller.positionBeats, 5);
      expect(
        controller.skippedPassages.single.reason,
        UnsupportedPassageReason.missingPitch,
      );
      expect(play(controller, 69).completed, isTrue);
    },
  );

  test('overlapping sustains and techniques are reported unsupported', () {
    final controller = PracticeProgressionController(
      timeline([
        TabBeat(position: 0, notes: [note(69, duration: 3)]),
        TabBeat(position: 1, notes: [note(71)]),
        TabBeat(position: 4, notes: [note(72, technique: 'harmonic')]),
        TabBeat(position: 6, notes: [note(74)]),
      ]),
    );
    expect(controller.skippedPassages.map((p) => p.reason), [
      UnsupportedPassageReason.overlappingNotes,
      UnsupportedPassageReason.technique,
    ]);
    play(controller, 69);
    expect(controller.positionBeats, 6);
    expect(play(controller, 74).completed, isTrue);
  });

  test('entirely unsupported, empty and invalid sections terminate even with looping', () {
    for (final beats in <List<TabBeat>>[
      [],
      [const TabBeat(position: 0, isRest: true)],
      [
        TabBeat(position: 0, notes: [note(null)]),
      ],
      [
        TabBeat(position: 0, notes: [note(128)]),
      ],
      [
        TabBeat(position: 0, notes: [note(69), note(72, string: 2)]),
      ],
      [
        TabBeat(position: -1, notes: [note(69)]),
      ],
    ]) {
      final controller = PracticeProgressionController(
        timeline(beats),
        looping: true,
      );
      expect(controller.completed, isTrue);
      expect(controller.observe(pitch(69)).looped, isFalse);
      expect(controller.loopCount, 0);
    }
  });

  test(
    'seek and restart clear partial matches and intentionally clear the latch',
    () {
      final controller = PracticeProgressionController(
        timeline([
          TabBeat(position: 0, notes: [note(69, duration: 2)]),
          TabBeat(position: 3, notes: [note(71)]),
          TabBeat(position: 5, notes: [note(72)]),
        ]),
      );
      controller.observe(pitch(69));
      controller.observe(pitch(69));
      controller.seek(0);
      expect(controller.observe(pitch(69)).matchedEvent, isNull);
      controller.restart();
      play(controller, 69);
      controller.seek(0);
      expect(play(controller, 69).matchedEvent, isNotNull);
      controller.seek(1); // No retroactive attack for the sustained first note.
      expect(controller.positionBeats, 3);
      controller.seek(99);
      expect(controller.completed, isTrue);
      controller.restart();
      expect(controller.positionBeats, 0);
      controller.seek(-10);
      expect(controller.positionBeats, 0);
      expect(() => controller.seek(double.nan), throwsArgumentError);
    },
  );

  test(
    'section endpoints are half open and section changes reset evidence',
    () {
      final controller = PracticeProgressionController(
        timeline([
          TabBeat(position: 0, notes: [note(69)]),
          TabBeat(position: 2, notes: [note(69)]),
          TabBeat(position: 4, notes: [note(71)]),
        ]),
      );
      controller.observe(pitch(69));
      controller.observe(pitch(69));
      controller.setSection(startBeat: 2, endBeat: 4);
      expect(controller.positionBeats, 2);
      expect(controller.observe(pitch(69)).matchedEvent, isNull);
      controller.observe(pitch(69));
      expect(controller.observe(pitch(69)).completed, isTrue);
      expect(controller.positionBeats, 4);
      controller.setSection(startBeat: 3, endBeat: 4);
      expect(controller.completed, isTrue);
      controller.setSection(startBeat: 2, endBeat: 2);
      expect(controller.completed, isTrue);
      for (final (start, end) in [
        (-1.0, 4.0),
        (4.0, 2.0),
        (0.0, 9.0),
        (0.0, double.infinity),
      ]) {
        expect(
          () => controller.setSection(startBeat: start, endBeat: end),
          throwsArgumentError,
        );
      }
    },
  );

  test('one-note loops preserve sustain latch and never reuse a confirmation frame', () {
    final controller = PracticeProgressionController(
      timeline([
        TabBeat(position: 2, notes: [note(69)]),
      ]),
      looping: true,
    );
    final result = play(controller, 69);
    expect(result.looped, isTrue);
    expect(result.completed, isFalse);
    expect(controller.positionBeats, 2);
    expect(controller.loopCount, 1);
    for (var i = 0; i < 10; i++) {
      expect(controller.observe(pitch(69)).matchedEvent, isNull);
    }
    expect(controller.loopCount, 1);
    controller.observe(null);
    controller.observe(null);
    expect(play(controller, 69).looped, isTrue);
    expect(controller.loopCount, 2);
    controller.setLooping(false);
    controller.observe(null);
    controller.observe(null);
    expect(play(controller, 69).completed, isTrue);
    controller.restart();
    expect(controller.loopCount, 0);
  });
}
