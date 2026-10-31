import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/structured_tab_viewer.dart';
import 'package:riffshelf/features/tabs/tab_detail_screen.dart';

void main() {
  testWidgets('empty tab shows a fallback', (tester) async {
    const tab = SavedTab(
      title: 'Empty',
      artist: '',
      source: '',
      sourceUrl: '',
      instrument: InstrumentType.guitar,
      stringCount: 6,
      tuning: ['E', 'A', 'D', 'G', 'B', 'E'],
    );
    await tester.pumpWidget(const MaterialApp(home: TabDetailScreen(tab: tab)));
    expect(find.text('No compatible tablature is available.'), findsOneWidget);
  });

  testWidgets('structured measures scroll horizontally', (tester) async {
    final tab = SavedTab(
      title: 'Long',
      artist: '',
      source: '',
      sourceUrl: '',
      instrument: InstrumentType.bass,
      stringCount: 4,
      tuning: const ['E', 'A', 'D', 'G'],
      measures: List.generate(
        8,
        (i) => TabMeasure(
          number: i + 1,
          beats: const [
            TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 3)]),
          ],
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: TabDetailScreen(tab: tab)));
    final scroll = find.byKey(const ValueKey('structured-4-strings'));
    await tester.drag(scroll, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SingleChildScrollView>(scroll).controller!.offset,
      greaterThan(0),
    );
  });
  for (final count in [4, 6]) {
    testWidgets('renders $count string lines and highlights active note', (
      tester,
    ) async {
      final tuning = count == 4
          ? ['E', 'A', 'D', 'G']
          : ['E', 'A', 'D', 'G', 'B', 'E'];
      final tab = SavedTab(
        title: 'Viewer',
        artist: 'Test',
        source: 'Test',
        sourceUrl: 'test://viewer',
        instrument: count == 4 ? InstrumentType.bass : InstrumentType.guitar,
        stringCount: count,
        tuning: tuning,
        measures: const [
          TabMeasure(
            number: 1,
            beats: [
              TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 3)]),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StructuredTabViewer(tab: tab)),
        ),
      );
      expect(find.byKey(ValueKey('structured-$count-strings')), findsOneWidget);
      for (var string = 1; string <= count; string++) {
        expect(find.byKey(ValueKey('string-1-$string')), findsOneWidget);
      }
      expect(find.text('3'), findsOneWidget);
    });
  }
}
