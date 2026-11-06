import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/database/tab_repository.dart';
import 'package:riffshelf/core/theme_provider.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/structured_tab_viewer.dart';
import 'package:riffshelf/features/tabs/tab_detail_screen.dart';

class TrackRepository implements TabRepository {
  TrackRepository(this.tabs);
  final List<SavedTab> tabs;
  @override
  Future<List<SavedTab>> findTabs([
    TabFilter filter = const TabFilter(),
  ]) async => tabs;
  @override
  Future<SavedTab?> getById(int id) async =>
      tabs.where((tab) => tab.id == id).firstOrNull;
  @override
  Future<SavedTab> save(SavedTab tab) async => tab;
  @override
  Future<void> delete(int id) async {}
  @override
  Future<Set<String>> allTags() async => {};
  @override
  Future<void> close() async {}
}

SavedTab track(
  int id,
  String name,
  String key, {
  String source = 'Local',
  String? sourceId,
}) => SavedTab(
  id: id,
  title: 'Song',
  artist: 'Artist',
  source: source,
  sourceId: sourceId,
  sourceUrl: 'same-name.gp',
  importKey: key,
  trackName: name,
  instrument: InstrumentType.guitar,
  stringCount: 4,
  tuning: const ['E', 'A', 'D', 'G'],
  asciiTab: 'G|--$id--|',
);

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
  for (final count in [4, 5, 6, 8]) {
    testWidgets('renders $count string lines and highlights active note', (
      tester,
    ) async {
      final tuning = List.generate(count, (index) => 'S$index');
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
  testWidgets('related imported tracks use file hash rather than filename', (
    tester,
  ) async {
    final hash = 'a' * 64;
    final otherHash = 'b' * 64;
    final first = track(1, 'Lead', 'sha256:$hash:track:0');
    final repo = TrackRepository([
      first,
      track(2, 'Bass', 'sha256:$hash:track:1'),
      track(3, 'Unrelated', 'sha256:$otherHash:track:0'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: TabDetailScreen(tab: first, repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lead · Guitar'));
    await tester.pumpAndSettle();
    expect(find.text('Bass · Guitar'), findsOneWidget);
    expect(find.text('Unrelated · Guitar'), findsNothing);
    await tester.tap(find.text('Bass · Guitar').last);
    await tester.pumpAndSettle();
    expect(find.text('G|--2--|'), findsOneWidget);
    expect(find.text('Choose album'), findsOneWidget);
    await tester.tap(find.text('Bass · Guitar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lead · Guitar').last);
    await tester.pumpAndSettle();
    expect(find.text('G|--1--|'), findsOneWidget);
  });

  testWidgets(
    'online track navigation only includes same provider and source ID',
    (tester) async {
      final first = track(
        1,
        'Lead',
        'online:Songsterr:19:lead',
        source: 'Songsterr',
        sourceId: '19',
      );
      final repo = TrackRepository([
        first,
        track(
          2,
          'Bass',
          'online:Songsterr:19:bass',
          source: 'Songsterr',
          sourceId: '19',
        ),
        track(
          3,
          'Different song',
          'online:Songsterr:20:lead',
          source: 'Songsterr',
          sourceId: '20',
        ),
        track(
          4,
          'Different source',
          'online:Other:19:lead',
          source: 'Other',
          sourceId: '19',
        ),
        track(
          5,
          'No identity',
          'unrecognized',
          source: 'Songsterr',
          sourceId: '19',
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: TabDetailScreen(tab: first, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lead · Guitar'));
      await tester.pumpAndSettle();
      expect(find.text('Bass · Guitar'), findsOneWidget);
      expect(find.text('Different song · Guitar'), findsNothing);
      expect(find.text('Different source · Guitar'), findsNothing);
      expect(find.text('No identity · Guitar'), findsNothing);
    },
  );

  testWidgets(
    'ASCII view preserves exact text when switching from structured view',
    (tester) async {
      const text = 'G|--0--|  \nD|--12-|\n  ending';
      const tab = SavedTab(
        title: 'Mixed',
        artist: 'A',
        source: 'Local',
        sourceUrl: '',
        instrument: InstrumentType.bass,
        stringCount: 4,
        tuning: ['E', 'A', 'D', 'G'],
        asciiTab: text,
        measures: [
          TabMeasure(
            number: 1,
            beats: [
              TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 3)]),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        const MaterialApp(home: TabDetailScreen(tab: tab)),
      );
      await tester.tap(find.text('ASCII'));
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
    },
  );

  for (final light in [true, false]) {
    testWidgets(
      'notes align with strings and beat positions with large text in ${light ? 'light' : 'dark'} mode',
      (tester) async {
        const tab = SavedTab(
          title: 'Position',
          artist: 'A',
          source: 'Local',
          sourceUrl: '',
          instrument: InstrumentType.bass,
          stringCount: 5,
          tuning: ['B', 'E', 'A', 'D', 'G'],
          measures: [
            TabMeasure(
              number: 1,
              beats: [
                TabBeat(
                  position: 0,
                  notes: [TabNote(stringNumber: 1, fret: 12)],
                ),
                TabBeat(
                  position: 2,
                  notes: [TabNote(stringNumber: 5, fret: 3)],
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeProvider().getTheme(light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: const Scaffold(
              body: StructuredTabViewer(tab: tab, activeBeat: 1),
            ),
          ),
        );
        final first = find.byKey(const ValueKey('note-0-0-1'));
        final second = find.byKey(const ValueKey('note-0-1-5'));
        expect(
          tester.getCenter(first).dy,
          closeTo(
            tester.getCenter(find.byKey(const ValueKey('string-1-1'))).dy,
            1,
          ),
        );
        expect(
          tester.getCenter(second).dy,
          closeTo(
            tester.getCenter(find.byKey(const ValueKey('string-1-5'))).dy,
            1,
          ),
        );
        expect(
          tester.getCenter(second).dx,
          greaterThan(tester.getCenter(first).dx),
        );
        final firstColor =
            (tester.widget<DecoratedBox>(first).decoration as BoxDecoration)
                .color;
        final secondColor =
            (tester.widget<DecoratedBox>(second).decoration as BoxDecoration)
                .color;
        expect(firstColor, isNot(secondColor));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
