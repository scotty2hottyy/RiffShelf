import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/database/tab_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/screens/library_screen.dart';

class MemoryRepository implements TabRepository {
  final List<SavedTab> data = [];
  TabFilter lastFilter = const TabFilter();
  @override
  Future<List<SavedTab>> findTabs([
    TabFilter filter = const TabFilter(),
  ]) async {
    lastFilter = filter;
    return data
        .where(
          (t) =>
              (!filter.favoritesOnly || t.isFavorite) &&
              (filter.query.isEmpty ||
                  t.title.toLowerCase().contains(filter.query.toLowerCase())),
        )
        .toList();
  }

  @override
  Future<SavedTab?> getById(int id) async =>
      data.where((t) => t.id == id).firstOrNull;
  @override
  Future<SavedTab> save(SavedTab tab) async {
    final index = data.indexWhere((t) => t.id == tab.id);
    if (index >= 0) {
      data[index] = tab;
    } else {
      data.add(tab);
    }
    return tab;
  }

  @override
  Future<Set<String>> allTags() async => data.expand((t) => t.tags).toSet();
  @override
  Future<void> delete(int id) async => data.removeWhere((t) => t.id == id);
  @override
  Future<void> close() async {}
}

SavedTab tab() => const SavedTab(
  id: 1,
  title: 'Offline song',
  artist: 'Artist',
  source: 'local',
  sourceUrl: 'source',
  instrument: InstrumentType.bass,
  classification: InstrumentClassification.other,
  stringCount: 4,
  tuning: ['?', '?', '?', '?'],
  asciiTab: 'G|--0--|\nD|--1--|',
  tags: ['old'],
);

void main() {
  testWidgets('applies and clears combined filter controls', (tester) async {
    final repo = MemoryRepository()..data.add(tab());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search title or artist'),
      'Offline',
    );
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any instrument'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bass').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any classification'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Electric').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'String count'), '4');
    await tester.enterText(
      find.widgetWithText(TextField, 'Tuning, low to high'),
      'E A D G',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Tags'),
      'rock, live',
    );
    await tester.ensureVisible(find.text('Favorites only'));
    await tester.tap(find.text('Favorites only'));
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(repo.lastFilter.query, 'Offline');
    expect(repo.lastFilter.instrument, InstrumentType.bass);
    expect(repo.lastFilter.classification, InstrumentClassification.electric);
    expect(repo.lastFilter.stringCount, 4);
    expect(repo.lastFilter.tuning, ['E', 'A', 'D', 'G']);
    expect(repo.lastFilter.tags, {'rock', 'live'});
    expect(repo.lastFilter.favoritesOnly, isTrue);
    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pumpAndSettle();
    expect(repo.lastFilter.query, isEmpty);
    expect(repo.lastFilter.instrument, isNull);
    expect(repo.lastFilter.favoritesOnly, isFalse);
  });
  testWidgets('empty library and delete confirmation, favorite and viewer', (
    tester,
  ) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No saved tabs match'), findsOneWidget);
    repo.data.add(tab());
    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Offline song'), findsOneWidget);
    expect(find.textContaining('? ? ? ?'), findsOneWidget);
    await tester.tap(find.byTooltip('Add favorite'));
    await tester.pumpAndSettle();
    expect(repo.data.single.isFavorite, isTrue);
    await tester.tap(find.text('Offline song'));
    await tester.pumpAndSettle();
    expect(find.text('G|--0--|\nD|--1--|'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tab options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.data, hasLength(1));
    await tester.tap(find.byTooltip('Tab options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(repo.data, isEmpty);
  });
  testWidgets('edits tags and tuning without changing content', (tester) async {
    final repo = MemoryRepository()..data.add(tab());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tab options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Tuning, low to high'),
      'E A D G',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Tags'),
      'New, jazz, new',
    );
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(repo.data.single.tags, ['New', 'jazz']);
    expect(repo.data.single.tuning, ['E', 'A', 'D', 'G']);
    expect(repo.data.single.classification, InstrumentClassification.other);
    expect(repo.data.single.asciiTab, tab().asciiTab);
    expect(repo.data.single.sourceUrl, 'source');
  });
}
