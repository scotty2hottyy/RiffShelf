import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/practice_session_screen.dart';

void main() {
  SavedTab buildTab() => SavedTab(
    title: 'Riff',
    artist: 'Test Artist',
    source: 'Test',
    sourceUrl: 'test://riff',
    instrument: InstrumentType.guitar,
    stringCount: 6,
    tuning: const ['E', 'A', 'D', 'G', 'B', 'E'],
    bpm: 120,
    measures: List.generate(
      4,
      (i) => TabMeasure(
        number: i + 1,
        beats: [
          TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: i)]),
          TabBeat(position: 2, notes: [TabNote(stringNumber: 2, fret: i + 1)]),
        ],
      ),
    ),
  );

  testWidgets('shows a fallback when there is no structured data', (
    tester,
  ) async {
    const tab = SavedTab(
      title: 'Empty',
      artist: '',
      source: '',
      sourceUrl: '',
      instrument: InstrumentType.guitar,
      stringCount: 6,
      tuning: ['E', 'A', 'D', 'G', 'B', 'E'],
    );
    await tester.pumpWidget(
      const MaterialApp(home: PracticeSessionScreen(tab: tab)),
    );
    expect(
      find.text(
        'Practice mode needs structured tab data, which isn\'t '
        'available for this tab.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('practice-track')), findsNothing);
  });

  testWidgets('renders the string lanes, playhead and starting measure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    expect(find.byKey(const ValueKey('practice-track')), findsOneWidget);
    expect(find.text('Measure 1 of 4'), findsOneWidget);
    expect(find.text('100% · 120 BPM'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('play advances the timeline right-to-left and pause stops it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );

    final painterBefore = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey('practice-track')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter;

    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    final painterDuring = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey('practice-track')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter;
    // Playback progressing repaints the track with a new elapsed position,
    // which is what drives notes drifting from right to left over time.
    expect(painterDuring, isNot(same(painterBefore)));

    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('dragging the track seeks and pauses playback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );

    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('practice-track')),
      const Offset(-120, 0),
    );
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('restart resets the measure indicator back to the start', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );

    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.text('Measure 1 of 4'), findsNothing);

    await tester.tap(find.byTooltip('Restart'));
    await tester.pump();
    expect(find.text('Measure 1 of 4'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('the speed slider rescales the effective BPM from the tab\'s '
      'own tempo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    expect(find.text('100% · 120 BPM'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('practice-speed-slider')),
      const Offset(-500, 0),
    );
    await tester.pump();

    expect(find.text('100% · 120 BPM'), findsNothing);
    expect(find.text('50% · 60 BPM'), findsOneWidget);
  });

  testWidgets('looping wraps playback back to the start instead of pausing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );

    // Max out speed so the short timeline wraps around quickly.
    await tester.drag(
      find.byKey(const ValueKey('practice-speed-slider')),
      const Offset(500, 0),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('practice-loop-toggle')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    // Advance well past the full timeline length multiple times over.
    await tester.pump(const Duration(seconds: 20));

    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without looping, playback pauses once it reaches the end', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );

    await tester.drag(
      find.byKey(const ValueKey('practice-speed-slider')),
      const Offset(500, 0),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('the metronome toggle runs during playback without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );

    await tester.tap(find.byKey(const ValueKey('practice-metronome-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(
      find.byKey(const ValueKey('practice-metronome-flash')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Stop playback (so no further ticks get scheduled) and let the
    // in-flight flash-reset timer drain before the widget tree is torn down.
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('the section control is hidden for a single-measure tab', (
    tester,
  ) async {
    final tab = SavedTab(
      title: 'Short',
      artist: '',
      source: '',
      sourceUrl: '',
      instrument: InstrumentType.guitar,
      stringCount: 6,
      tuning: const ['E', 'A', 'D', 'G', 'B', 'E'],
      measures: const [
        TabMeasure(
          number: 1,
          beats: [
            TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 0)]),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: PracticeSessionScreen(tab: tab)));

    expect(find.byKey(const ValueKey('practice-section-slider')), findsNothing);
  });

  testWidgets(
    'narrowing the practice section enables looping just that range',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
      );

      expect(find.text('Whole song'), findsOneWidget);
      final resetButtonBefore = tester.widget<IconButton>(
        find.byKey(const ValueKey('practice-section-reset')),
      );
      expect(resetButtonBefore.onPressed, isNull);

      final sliderRect = tester.getRect(
        find.byKey(const ValueKey('practice-section-slider')),
      );
      // Drag the start thumb (resting at the left edge) inward.
      await tester.dragFrom(
        sliderRect.centerLeft + const Offset(4, 0),
        Offset(sliderRect.width * 0.4, 0),
      );
      await tester.pump();

      expect(find.text('Whole song'), findsNothing);
      final resetButtonAfter = tester.widget<IconButton>(
        find.byKey(const ValueKey('practice-section-reset')),
      );
      expect(resetButtonAfter.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('practice-section-reset')));
      await tester.pump();
      expect(find.text('Whole song'), findsOneWidget);
    },
  );
}
