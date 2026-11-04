import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/import/tab_import_service.dart';
import 'package:riffshelf/features/tabs/practice_timeline.dart';

void main() {
  test('GP3, GP4 and GP5 imported chords retain authored timing', () {
    const importer = TabImportService();
    for (final extension in ['gp3', 'gp4', 'gp5']) {
      final name = 'Chords.$extension';
      final document = importer.parseGuitarPro(
        File('test/fixtures/$name').readAsBytesSync(),
      );
      final tab = importer.convertTrack(document, 0, name);
      final timeline = PracticeTimeline.fromTab(tab);
      expect(timeline.hasReliableTiming, isTrue, reason: name);
      expect(timeline.totalBeats, 32, reason: name);
      expect(timeline.measures.map((m) => m.startBeat), [
        0,
        4,
        8,
        12,
        16,
        20,
        24,
        28,
      ], reason: name);
      expect(timeline.events.length, 78, reason: name);
      expect(timeline.events.take(5).map((e) => e.stringNumber), [
        1,
        2,
        3,
        4,
        5,
      ], reason: name);
      expect(timeline.events.take(5).map((e) => e.startBeat), [
        0,
        0,
        0,
        0,
        0,
      ], reason: name);
      expect(timeline.events.take(5).map((e) => e.durationBeats), [
        2,
        2,
        2,
        2,
        2,
      ], reason: name);
      expect(timeline.events[5].startBeat, 2, reason: name);
    }
  });

  test('GPX imported sustained note uses its four-beat duration', () {
    const importer = TabImportService();
    final document = importer.parseGuitarPro(
      File('test/fixtures/synthetic.gpx').readAsBytesSync(),
    );
    final timeline = PracticeTimeline.fromTab(
      importer.convertTrack(document, 0, 'synthetic.gpx'),
    );
    expect(timeline.hasReliableTiming, isTrue);
    expect(timeline.events.single.startBeat, 0);
    expect(timeline.events.single.durationBeats, 4);
    expect(timeline.events.single.endBeat, 4);
  });

  SavedTab tabWithMeasures(
    List<TabMeasure> measures, {
    List<String> tuning = const ['E', 'A', 'D', 'G', 'B', 'E'],
    InstrumentType instrument = InstrumentType.guitar,
    TabType tabType = TabType.tab,
  }) => SavedTab(
    title: 'Timeline',
    artist: '',
    source: '',
    sourceUrl: '',
    instrument: instrument,
    stringCount: tuning.length,
    tuning: tuning,
    tabType: tabType,
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

  test('four-, five-, and six-string alternate tunings keep chord lanes', () {
    for (final tuning in [
      ['D1', 'G1', 'C2', 'F2'],
      ['B0', 'E1', 'A1', 'D2', 'G2'],
      ['D2', 'A2', 'D3', 'G3', 'A3', 'D4'],
    ]) {
      final timeline = PracticeTimeline.fromTab(
        tabWithMeasures(
          [
            TabMeasure(
              number: 1,
              beats: [
                TabBeat(
                  position: 0,
                  notes: [
                    const TabNote(stringNumber: 1, fret: 0, duration: 3),
                    TabNote(stringNumber: tuning.length, fret: 5),
                  ],
                ),
                const TabBeat(position: 1, isRest: true),
                const TabBeat(
                  position: 3,
                  notes: [TabNote(stringNumber: 2, fret: 2)],
                ),
              ],
            ),
            const TabMeasure(number: 2, beats: []),
          ],
          tuning: tuning,
          instrument: tuning.length < 6
              ? InstrumentType.bass
              : InstrumentType.guitar,
        ),
      );
      expect(timeline.hasReliableTiming, isTrue);
      expect(timeline.totalBeats, 8);
      expect(timeline.events.map((e) => e.startBeat), [0, 0, 3]);
      expect(timeline.events.map((e) => e.stringNumber), [1, tuning.length, 2]);
      expect(timeline.events.first.endBeat, 3);
    }
  });

  test(
    'invalid string, nonfinite timing, and unsupported format fall back',
    () {
      for (final measure in [
        const TabMeasure(
          number: 1,
          beats: [
            TabBeat(position: 0, notes: [TabNote(stringNumber: 7, fret: 1)]),
          ],
        ),
        const TabMeasure(
          number: 1,
          beats: [
            TabBeat(
              position: double.nan,
              notes: [TabNote(stringNumber: 1, fret: 1)],
            ),
          ],
        ),
        const TabMeasure(
          number: 1,
          beats: [
            TabBeat(
              position: 0,
              duration: double.infinity,
              notes: [TabNote(stringNumber: 1, fret: 1)],
            ),
          ],
        ),
      ]) {
        final timeline = PracticeTimeline.fromTab(tabWithMeasures([measure]));
        expect(timeline.hasReliableTiming, isFalse);
        expect(timeline.events, isEmpty);
      }
      final unsupported = PracticeTimeline.fromTab(
        tabWithMeasures([
          const TabMeasure(
            number: 1,
            beats: [
              TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 1)]),
            ],
          ),
        ], tabType: TabType.other),
      );
      expect(unsupported.hasReliableTiming, isFalse);
    },
  );

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

    final overridden = timeline.events.firstWhere((e) => e.stringNumber == 1);
    final fallback = timeline.events.firstWhere((e) => e.stringNumber == 2);
    expect(overridden.durationBeats, 2.5);
    expect(fallback.durationBeats, 1);
  });

  test('rejects zero and negative durations instead of inventing timing', () {
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

    expect(timeline.hasReliableTiming, isFalse);
    expect(timeline.events, isEmpty);
  });

  test('rejects a beat position outside of its measure bounds', () {
    final tab = tabWithMeasures([
      const TabMeasure(
        number: 1,
        beats: [
          TabBeat(position: -2, notes: [TabNote(stringNumber: 1, fret: 0)]),
          TabBeat(position: 99, notes: [TabNote(stringNumber: 2, fret: 1)]),
        ],
      ),
    ]);

    final timeline = PracticeTimeline.fromTab(tab);

    expect(timeline.hasReliableTiming, isFalse);
    expect(timeline.events, isEmpty);
  });

  test('rejects an invalid time signature', () {
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

    expect(timeline.hasReliableTiming, isFalse);
    expect(timeline.totalBeats, 0);
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
