import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:riffshelf/core/theme_provider.dart';
import 'package:riffshelf/features/artwork/album_art.dart';

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
  int searchCalls = 0;
  TabSearchQuery? lastQuery;
  @override
  String get name => 'Mock';
  @override
  Future<List<TabSearchResult>> search(TabSearchQuery query) {
    searchCalls++;
    lastQuery = query;
    return pending.future;
  }

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

class FailingProvider implements TabSourceProvider {
  @override
  String get name => 'Unavailable';
  @override
  Future<List<TabSearchResult>> search(TabSearchQuery query) async =>
      throw const TabProviderException('Offline');
  @override
  Future<SavedTab> fetchTab(TabSearchResult result) async =>
      throw UnimplementedError();
}

class BackendSearch implements TabSearchProvider {
  TabSearchQuery? lastQuery;
  @override
  Future<List<TabSearchResult>> search(TabSearchQuery query) async {
    lastQuery = query;
    return [result];
  }
}

class MemoryRepository implements TabRepository {
  final tabs = <SavedTab>[];
  bool duplicate = false;
  @override
  Future<SavedTab> save(SavedTab tab) async {
    if (duplicate) throw const DuplicateTabException();
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
  Future<void> mount(WidgetTester tester) async {
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
  }

  Future<void> start(WidgetTester tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.text('Search'));
    await tester.pump();
  }

  bool fieldHasFocus(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

  testWidgets('Search button dismisses keyboard and searches', (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Song');
    expect(fieldHasFocus(tester), isTrue);
    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(fieldHasFocus(tester), isFalse);
    expect(provider.searchCalls, 1);
  });

  testWidgets('keyboard Search key dismisses keyboard and searches', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Song');
    expect(fieldHasFocus(tester), isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(fieldHasFocus(tester), isFalse);
    expect(provider.searchCalls, 1);
  });

  testWidgets('tapping outside the field dismisses keyboard', (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Song');
    expect(fieldHasFocus(tester), isTrue);
    await tester.tapAt(const Offset(300, 300));
    await tester.pump();
    expect(fieldHasFocus(tester), isFalse);
    expect(provider.searchCalls, 0);
  });

  testWidgets('dragging results dismisses keyboard', (tester) async {
    await start(tester);
    provider.pending.complete([
      for (var index = 0; index < 20; index++)
        TabSearchResult(
          externalId: '$index',
          title: 'Song $index',
          artist: 'Artist',
          instrument: InstrumentType.guitar,
          sourceName: 'Mock',
          sourceUrl: 'https://example.com/$index',
        ),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(fieldHasFocus(tester), isTrue);
    final focus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });

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
  testWidgets('Save on card preserves selection and duplicate validation', (
    tester,
  ) async {
    repository.duplicate = true;
    await start(tester);
    provider.pending.complete([result]);
    await tester.pumpAndSettle();
    expect(find.text('Artist'), findsOneWidget);
    expect(find.text('Guitar'), findsOneWidget);
    expect(find.text('Mock'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an arrangement'), findsOneWidget);
    await tester.tap(find.textContaining('Lead · Guitar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Library'));
    await tester.pumpAndSettle();
    expect(
      find.text('This arrangement is already in your library.'),
      findsOneWidget,
    );
    expect(repository.tabs, isEmpty);
  });

  testWidgets('instrument selection reaches search', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Guitar and bass'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bass').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(provider.lastQuery!.instrument, InstrumentType.bass);
    provider.pending.complete([]);
    await tester.pumpAndSettle();
  });

  for (final light in [true, false]) {
    testWidgets(
      'cards fit small screens with large text in ${light ? 'light' : 'dark'} mode',
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
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: DiscoverScreen(
                service: TabSearchService([provider]),
                repository: repository,
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), 'Song');
        await tester.ensureVisible(find.text('Search'));
        await tester.tap(find.text('Search'));
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        provider.pending.complete([
          const TabSearchResult(
            externalId: '1',
            title: 'A long song title for a small screen',
            artist: 'A long artist name',
            instrument: InstrumentType.bass,
            sourceName: 'Mock',
            sourceUrl: 'https://example.com',
            tuning: ['E', 'A', 'D', 'G'],
          ),
        ]);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        await tester.scrollUntilVisible(
          find.text('Save'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(find.text('E A D G'), findsOneWidget);
        expect(find.text('Bass'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'uses matching saved artwork and falls back when file is missing',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('discover_art'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cover.png');
      await tester.runAsync(
        () => file.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        ),
      );
      repository.tabs.add(
        SavedTab(
          id: 1,
          title: 'Song',
          artist: 'Artist',
          source: 'Mock',
          sourceId: '1',
          sourceUrl: result.sourceUrl,
          instrument: InstrumentType.guitar,
          stringCount: 2,
          tuning: const ['E', 'A'],
          asciiTab: 'E|-0-',
          artwork: jsonEncode({'local_path': file.path}),
        ),
      );
      await start(tester);
      provider.pending.complete([result]);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AlbumArt>(find.byType(AlbumArt)).tab.artwork,
        isNotNull,
      );
      expect(find.byType(Image), findsOneWidget);
      await tester.runAsync(() => file.delete());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      // A fresh result with no matching saved artwork uses the same offline fallback.
      repository.tabs.clear();
      provider.pending = Completer();
      await tester.tap(find.text('Search'));
      await tester.pump();
      provider.pending.complete([result]);
      await tester.pumpAndSettle();
      // Refreshing artwork occurs when returning from preview; verify the reusable widget's missing-file fallback separately.
      await tester.pumpWidget(
        MaterialApp(
          home: AlbumArt(
            tab: SavedTab(
              title: 'Song',
              artist: 'Artist',
              source: 'Mock',
              sourceUrl: '',
              instrument: InstrumentType.guitar,
              stringCount: 1,
              tuning: const [],
              artwork: jsonEncode({'local_path': '${dir.path}/missing.png'}),
            ),
            size: 70,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.album_outlined), findsOneWidget);
    },
  );
  testWidgets('partial provider failures leave results usable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoverScreen(
            service: TabSearchService([provider, FailingProvider()]),
            repository: repository,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.text('Search'));
    await tester.pump();
    provider.pending.complete([result]);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Some providers are unavailable: Unavailable'),
      findsOneWidget,
    );
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets(
    'configured backend search still displays cards and fetches via source',
    (tester) async {
      final backend = BackendSearch();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverScreen(
              service: TabSearchService([provider], searchProvider: backend),
              repository: repository,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Song');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(backend.lastQuery!.text, 'Song');
      expect(provider.searchCalls, 0);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Choose an arrangement'), findsOneWidget);
    },
  );
}
