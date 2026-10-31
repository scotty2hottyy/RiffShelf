import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/database/tab_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/features/search/application/tab_search_service.dart';
import 'package:riffshelf/features/search/domain/tab_source_provider.dart';
import 'package:riffshelf/screens/discover_screen.dart';

const result = TabSearchResult(
  externalId: '1',
  title: 'Song',
  artist: 'Artist',
  instrument: InstrumentType.guitar,
  sourceName: 'Mock',
  sourceUrl: 'https://example.com',
);

class Provider implements TabSourceProvider, TrackSelectableTabSourceProvider {
  Completer<List<TabSearchResult>> pending = Completer();
  @override
  String get name => 'Mock';
  @override
  Future<List<TabSearchResult>> search(TabSearchQuery query) => pending.future;
  @override
  Future<SavedTab> fetchTab(TabSearchResult result) async =>
      throw const TabTrackSelectionException([
        TabTrackOption(
          id: '1',
          name: 'Lead',
          instrument: 'Guitar',
          tuning: ['E', 'A'],
        ),
      ]);
  @override
  Future<SavedTab> fetchTabTrack(
    TabSearchResult result,
    TabTrackOption option,
  ) async => SavedTab(
    title: 'Song',
    artist: 'Artist',
    source: name,
    sourceUrl: result.sourceUrl,
    instrument: InstrumentType.guitar,
    stringCount: 2,
    tuning: const ['E', 'A'],
    trackName: option.name,
    asciiTab: 'e|--2--|\nB|-----|',
  );
}

class MemoryRepository implements TabRepository {
  final tabs = <SavedTab>[];
  @override
  Future<SavedTab> save(SavedTab tab) async {
    final saved = tab.copyWith(id: 1);
    tabs.add(saved);
    return saved;
  }

  @override
  Future<List<SavedTab>> findTabs([
    TabFilter filter = const TabFilter(),
  ]) async => tabs;
  @override
  Future<SavedTab?> getById(int id) async =>
      tabs.where((t) => t.id == id).firstOrNull;
  @override
  Future<Set<String>> allTags() async => {};
  @override
  Future<void> delete(int id) async => tabs.removeWhere((t) => t.id == id);
  @override
  Future<void> close() async {}
}

void main() {
  late MemoryRepository repository;
  late Provider provider;
  setUp(() {
    repository = MemoryRepository();
    provider = Provider();
  });
  tearDown(() async => repository.close());
  Future<void> start(WidgetTester tester) async {
    provider.pending = Completer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoverScreen(
            service: TabSearchService([provider]),
            repository: repository,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.text('Search'));
    await tester.pump();
  }

  testWidgets('loading and empty states', (tester) async {
    await start(tester);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    provider.pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No results found.'), findsOneWidget);
  });
  testWidgets('error and retry states', (tester) async {
    await start(tester);
    provider.pending.completeError(const TabProviderException('Offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline'), findsOneWidget);
    provider.pending = Completer();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    provider.pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No results found.'), findsOneWidget);
  });
  testWidgets('choose track, preview, save, and reload offline', (
    tester,
  ) async {
    await start(tester);
    provider.pending.complete([result]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Choose an arrangement'), findsOneWidget);
    await tester.tap(find.textContaining('Lead · Guitar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('e|--2--|'), findsOneWidget);
    await tester.tap(find.text('Save to Library'));
    await tester.pumpAndSettle();
    expect(find.text('Saved to Library'), findsOneWidget);
    final tabs = await repository.findTabs();
    expect(tabs.single.trackName, 'Lead');
    expect(
      (await repository.getById(tabs.single.id!))!.asciiTab,
      contains('2'),
    );
  });
}
