import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/practice_timeline.dart';

void main() {
  SavedTab tabWithMeasures(List<TabMeasure> measures) => SavedTab(
    title: 'Timeline',
    artist: '',
    source: '',
    sourceUrl: '',
    instrument: InstrumentType.guitar,
    stringCount: 6,
    tuning: const ['E', 'A', 'D', 'G', 'B', 'E'],
    measures: measures,
  );

  test('flattens notes onto an absolute beat timeline across measures', () {
    final tab = tabWithMeasures([
      const TabMeasure(
        number: 1,
        beats: [
          TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 0)]),
          TabBeat(position: 2, notes: [TabNote(stringNumber: 2, fret: 1)]),
        ],
      ),
      const TabMeasure(
        number: 2,
        beats: [
          TabBeat(position: 0, notes: [TabNote(stringNumber: 3, fret: 2)]),
        ],
      ),
    ]);

    final timeline = PracticeTimeline.fromTab(tab);

    expect(timeline.totalBeats, 8);
    expect(timeline.measures.map((m) => m.startBeat), [0, 4]);
    expect(timeline.events.map((e) => e.startBeat), [0, 2, 4]);
    expect(timeline.events[2].measureNumber, 2);
  });

  test('sorts beats that arrive out of order within a measure', () {
    final tab = tabWithMeasures([
      const TabMeasure(
        number: 1,
        beats: [
          TabBeat(position: 3, notes: [TabNote(stringNumber: 1, fret: 9)]),
          TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 0)]),
          TabBeat(position: 1, notes: [TabNote(stringNumber: 1, fret: 5)]),
        ],
      ),
    ]);

    final timeline = PracticeTimeline.fromTab(tab);

    expect(timeline.events.map((e) => e.startBeat), [0, 1, 3]);
    expect(timeline.events.map((e) => e.fret), [0, 5, 9]);
  });

  test('note-level duration overrides the beat-level default', () {
    final tab = tabWithMeasures([
      const TabMeasure(
        number: 1,
        beats: [
          TabBeat(
            position: 0,
            duration: 1,
            notes: [
              TabNote(stringNumber: 1, fret: 3, duration: 2.5),
              TabNote(stringNumber: 2, fret: 5),
            ],
          ),
        ],
      ),
    ]);

    final timeline = PracticeTimeline.fromTab(tab);

    final overridden = timeline.events.firstWhere(
      (e) => e.stringNumber == 1,
    );
    final fallback = timeline.events.firstWhere((e) => e.stringNumber == 2);
    expect(overridden.durationBeats, 2.5);
    expect(fallback.durationBeats, 1);
  });

  test('clamps zero, negative, or missing durations to a visible minimum', () {
    final tab = tabWithMeasures([
      const TabMeasure(
        number: 1,
        beats: [
          TabBeat(
            position: 0,
            duration: 0,
            notes: [TabNote(stringNumber: 1, fret: 1)],
          ),
          TabBeat(
            position: 1,
            duration: -3,
            notes: [TabNote(stringNumber: 2, fret: 2)],
          ),
        ],
      ),
    ]);

    final timeline = PracticeTimeline.fromTab(tab);

    expect(
      timeline.events.every((e) => e.durationBeats >= minNoteDurationBeats),
      isTrue,
    );
  });

  test('clamps a beat position outside of its measure bounds', () {
    final tab = tabWithMeasures([
      const TabMeasure(
        number: 1,
        beats: [
          TabBeat(
            position: -2,
            notes: [TabNote(stringNumber: 1, fret: 0)],
          ),
          TabBeat(
            position: 99,
            notes: [TabNote(stringNumber: 2, fret: 1)],
          ),
        ],
      ),
    ]);

    final timeline = PracticeTimeline.fromTab(tab);

    expect(timeline.events.first.startBeat, 0);
    expect(timeline.events.last.startBeat, 4);
  });

  test('falls back to 4/4 for an invalid time signature instead of NaN', () {
    final tab = tabWithMeasures([
      const TabMeasure(
        number: 1,
        numerator: 0,
        denominator: 0,
        beats: [
          TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 0)]),
        ],
      ),
      const TabMeasure(number: 2, beats: []),
    ]);

    final timeline = PracticeTimeline.fromTab(tab);

    expect(timeline.measures[1].startBeat, 4);
    expect(timeline.totalBeats, 8);
  });

  test('keeps distinct strings at the same beat (a chord)', () {
    final tab = tabWithMeasures([
      const TabMeasure(
        number: 1,
        beats: [
          TabBeat(
            position: 0,
            notes: [
              TabNote(stringNumber: 1, fret: 0),
              TabNote(stringNumber: 2, fret: 2),
              TabNote(stringNumber: 3, fret: 2),
            ],
          ),
        ],
      ),
    ]);

    final timeline = PracticeTimeline.fromTab(tab);

    expect(timeline.events, hasLength(3));
    expect(timeline.events.map((e) => e.startBeat), [0, 0, 0]);
  });

  test('collapses an exact duplicate note at the same string and beat', () {
    final tab = tabWithMeasures([
      const TabMeasure(
        number: 1,
        beats: [
          TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 3)]),
          TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 7)]),
        ],
      ),
    ]);

    final timeline = PracticeTimeline.fromTab(tab);

    expect(timeline.events, hasLength(1));
    expect(timeline.events.single.fret, 7);
  });

  test('an empty tab yields an empty, zero-length timeline', () {
    final timeline = PracticeTimeline.fromTab(tabWithMeasures(const []));

    expect(timeline.events, isEmpty);
    expect(timeline.measures, isEmpty);
    expect(timeline.totalBeats, 0);
  });
}
