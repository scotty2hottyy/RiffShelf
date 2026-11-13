import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/core/models/tuning.dart';
import 'package:riffshelf/features/tabs/practice_preparation_screen.dart';
import 'package:riffshelf/features/tabs/practice_session_screen.dart';
import 'package:riffshelf/features/tabs/tab_detail_screen.dart';
import 'package:riffshelf/screens/tuner_screen.dart';

void main() {
  SavedTab tab(InstrumentType instrument, List<String> tuning) => SavedTab(
    title: 'Selected song',
    artist: 'Artist',
    trackName: 'Selected arrangement',
    source: 'Fixture',
    sourceUrl: '',
    instrument: instrument,
    stringCount: tuning.length,
    tuning: tuning,
    measures: const [
      TabMeasure(
        number: 1,
        beats: [
          TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 0)]),
        ],
      ),
    ],
  );

  for (final instrument in [InstrumentType.guitar, InstrumentType.bass]) {
    testWidgets('${instrument.name} tuning and skipping preserve arrangement', (
      tester,
    ) async {
      final selected = tab(
        instrument,
        instrument == InstrumentType.bass
            ? ['D1', 'G1', 'C2', 'F2']
            : ['D2', 'A2', 'D3', 'G3', 'A3', 'D4'],
      );
      await tester.pumpWidget(
        MaterialApp(home: PracticePreparationScreen(tab: selected)),
      );
      await tester.tap(find.text('Tune instrument'));
      await tester.pumpAndSettle();
      final tuner = tester.widget<TunerScreen>(find.byType(TunerScreen));
      expect(tuner.preset!.notes, selected.tuning);
      expect(
        tuner.preset!.instrument,
        TunerInstrument.fromTabInstrument(instrument),
      );
      expect(find.text('Start tuning'), findsOneWidget);
      await tester.tap(find.text('Done tuning'));
      await tester.pumpAndSettle();
      expect(find.text('Selected arrangement'), findsOneWidget);
      await tester.tap(find.text('Start practice'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PracticeSessionScreen>(find.byType(PracticeSessionScreen))
            .tab,
        same(selected),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Selected arrangement'), findsOneWidget);
    });
  }

  testWidgets('unknown octaves disable tuning but allow practice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PracticePreparationScreen(
          tab: tab(InstrumentType.guitar, ['E', 'A', 'D', 'G', 'B', 'E']),
        ),
      ),
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Tune instrument'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Start practice'));
    await tester.pumpAndSettle();
    expect(find.byType(PracticeSessionScreen), findsOneWidget);
  });

  testWidgets('tab detail practice action opens preparation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TabDetailScreen(
          tab: tab(InstrumentType.bass, ['E1', 'A1', 'D2', 'G2']),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Practice'));
    await tester.pumpAndSettle();
    expect(find.byType(PracticePreparationScreen), findsOneWidget);
  });
}
