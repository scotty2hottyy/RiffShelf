import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/theme_provider.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/practice_session_screen.dart';

void main() {
  SavedTab buildTab({int bpm = 120}) => SavedTab(
    title: 'Riff',
    artist: 'Test Artist',
    source: 'Test',
    sourceUrl: 'test://riff',
    instrument: InstrumentType.guitar,
    stringCount: 6,
    tuning: const ['E', 'A', 'D', 'G', 'B', 'E'],
    bpm: bpm,
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
      find.textContaining('Practice mode needs structured tab data'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('practice-track')), findsNothing);
  });

  testWidgets(
    'invalid timing displays static notes without playback controls',
    (tester) async {
      final tab = SavedTab(
        title: 'Damaged',
        artist: '',
        source: '',
        sourceUrl: '',
        instrument: InstrumentType.bass,
        stringCount: 4,
        tuning: const ['D1', 'G1', 'C2', 'F2'],
        measures: const [
          TabMeasure(
            number: 1,
            numerator: 0,
            beats: [
              TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 5)]),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: PracticeSessionScreen(tab: tab)),
      );
      expect(
        find.textContaining('Timed practice is unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('Measure 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('practice-track')), findsNothing);
      expect(find.byKey(const ValueKey('practice-play-pause')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('repeated pause, seek, speed and replay stay within boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('practice-track')),
        const Offset(-100, 0),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('practice-speed-75')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('Restart'));
    await tester.pump();
    expect(find.text('Measure 1 of 4'), findsOneWidget);
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

  testWidgets('all five speed positions use the exact tab tempo multiplier', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    expect(find.text('100% · 120 BPM'), findsOneWidget);

    for (final (speed, bpm) in [
      (25, 30),
      (50, 60),
      (75, 90),
      (100, 120),
      (150, 180),
    ]) {
      await tester.tap(find.byKey(ValueKey('practice-speed-$speed')));
      await tester.pump();
      expect(find.text('$speed% · $bpm BPM'), findsOneWidget);
    }
  });

  testWidgets('changing speed during playback keeps the current measure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.text('Measure 2 of 4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('practice-speed-25')));
    await tester.pump();
    expect(find.text('Measure 2 of 4'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Measure 2 of 4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('practice-speed-150')));
    await tester.pump();
    expect(find.text('Measure 2 of 4'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Measure 3 of 4'), findsOneWidget);
  });

  testWidgets('150% is not capped for a fast authored tempo', (tester) async {
    final tab = buildTab(bpm: 300);
    await tester.pumpWidget(MaterialApp(home: PracticeSessionScreen(tab: tab)));
    await tester.tap(find.byKey(const ValueKey('practice-speed-150')));
    await tester.pump();
    expect(find.text('150% · 450 BPM'), findsOneWidget);
  });

  testWidgets('looping wraps playback back to the start instead of pausing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );

    // Max out speed so the short timeline wraps around quickly.
    await tester.tap(find.byKey(const ValueKey('practice-speed-150')));
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

  testWidgets('whole song wraps at the exact measure boundary', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    await tester.tap(find.byKey(const ValueKey('practice-loop-toggle')));
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8100));
    expect(find.text('Measure 1 of 4'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets(
    'section changes pause, reposition and wrap without extra beats',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
      );
      await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
      await tester.pump();
      tester
          .widget<RangeSlider>(
            find.byKey(const ValueKey('practice-section-slider')),
          )
          .onChanged!(const RangeValues(1, 2));
      await tester.pump();
      expect(find.text('Measure 2 of 4'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('practice-loop-toggle')));
      await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 4100));
      expect(find.text('Measure 2 of 4'), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    },
  );

  testWidgets('a non-looping section stops before the following measure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    tester
        .widget<RangeSlider>(
          find.byKey(const ValueKey('practice-section-slider')),
        )
        .onChanged!(const RangeValues(1, 2));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3900));
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    // The playhead is exactly at the boundary, not four beats beyond it.
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    expect(find.text('Measure 2 of 4'), findsOneWidget);
  });

  testWidgets('background pauses and resume does not advance the position', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.text('Measure 2 of 4'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('Measure 2 of 4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Measure 2 of 4'), findsOneWidget);
  });

  testWidgets('metronome clicks once at a loop boundary', (tester) async {
    final sounds = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemSound.play') sounds.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    await tester.tap(find.byKey(const ValueKey('practice-loop-toggle')));
    await tester.tap(find.byKey(const ValueKey('practice-metronome-toggle')));
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 7900));
    sounds.clear();
    await tester.pump(const Duration(milliseconds: 100));
    expect(sounds, hasLength(1));
    expect(sounds.single.arguments, 'SystemSoundType.alert');
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('without looping, playback pauses once it reaches the end', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );

    await tester.tap(find.byKey(const ValueKey('practice-speed-150')));
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
  testWidgets('hit line remains fixed while progress and notes advance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    final line = find.byKey(const ValueKey('practice-hit-line'));
    final track = find.byKey(const ValueKey('practice-track'));
    final start = tester.getTopLeft(line).dx;
    final relative = start - tester.getTopLeft(track).dx;
    expect(relative, closeTo(36, .01));
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('practice-progress')),
          )
          .value,
      0,
    );
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getTopLeft(line).dx, closeTo(start, .01));
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('practice-progress')),
          )
          .value!,
      greaterThan(0),
    );
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
  });

  testWidgets('zoom clamps floating-point overshoot at both endpoints', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    // Continuous sliders denormalize their position using this calculation.
    // Its rounded result is slightly greater than the declared maximum.
    final upperEndpoint = 0.6 + (1.8 - 0.6);
    expect(upperEndpoint, greaterThan(1.8));
    final zoom = find.byType(Slider);
    tester.widget<Slider>(zoom).onChanged!(upperEndpoint);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Slider>(zoom).value, 1.8);
    tester.widget<Slider>(zoom).onChanged!(0.6 - 1e-15);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Slider>(zoom).value, 0.6);
  });

  testWidgets('dragging zoom to both ends repeatedly stays in range', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    final zoom = find.byType(Slider);
    await tester.ensureVisible(zoom);
    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(zoom);
      await tester.pumpAndSettle();
      await tester.drag(zoom, const Offset(2000, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.widget<Slider>(zoom).value, 1.8);
      // Zoom changes the content height, so scroll the control back into view.
      await tester.ensureVisible(zoom);
      await tester.pumpAndSettle();
      await tester.drag(zoom, const Offset(-2000, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.widget<Slider>(zoom).value, 0.6);
    }
  });

  for (final light in [true, false]) {
    testWidgets(
      'practice fits small screens and large text in ${light ? 'light' : 'dark'} theme',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeProvider().getTheme(light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: PracticeSessionScreen(tab: buildTab()),
          ),
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('practice-play-pause')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('practice-hit-line')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('practice-speed-150')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('practice toggles expose their on-off state to accessibility', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PracticeSessionScreen(tab: buildTab())),
    );
    final loop = find.byKey(const ValueKey('practice-loop-toggle'));
    Semantics state() => tester.widget<Semantics>(
      find
          .ancestor(
            of: loop,
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.toggled != null,
            ),
          )
          .first,
    );
    expect(state().properties.toggled, isFalse);
    await tester.tap(loop);
    await tester.pump();
    expect(state().properties.toggled, isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('practice-speed-100'))).height,
      greaterThanOrEqualTo(48),
    );
  });
}
