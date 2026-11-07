import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:riffshelf/core/theme_provider.dart';
import 'package:riffshelf/features/artwork/album_art.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/database/tab_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/screens/library_screen.dart';
import 'package:riffshelf/screens/practice_screen.dart';

class FailingPicker extends FilePickerPlatform {
  int calls = 0;
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    if (calls == 1) throw StateError('Picker unavailable');
    return [];
  }
}

class MemoryRepository implements TabRepository {
  final List<SavedTab> data = [];
  TabFilter lastFilter = const TabFilter();
  bool failLoad = false;
  bool failDelete = false;
  @override
  Future<List<SavedTab>> findTabs([
    TabFilter filter = const TabFilter(),
  ]) async {
    lastFilter = filter;
    if (failLoad) throw StateError('storage failure');
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
  Future<void> delete(int id) async {
    if (failDelete) throw StateError('storage failure');
    data.removeWhere((t) => t.id == id);
  }

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
    expect(find.text('Tag: rock'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove rock tag filter'));
    await tester.pumpAndSettle();
    expect(repo.lastFilter.tags, {'live'});
    await tester.tap(find.byTooltip('Remove favorites filter'));
    await tester.pumpAndSettle();
    expect(repo.lastFilter.favoritesOnly, isFalse);
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
    expect(find.byTooltip('Remove favorite'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'old'), findsOneWidget);
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
  for (final light in [true, false]) {
    testWidgets(
      'library cards support small screens and large text in ${light ? 'light' : 'dark'} theme',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = MemoryRepository()..data.add(tab());
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeProvider().getTheme(light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(body: LibraryScreen(repository: repo)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byTooltip('Add favorite'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Offline song'), findsOneWidget);
        expect(
          find.text('local'),
          findsNothing,
        ); // Source is part of the metadata line.
        expect(find.textContaining('local'), findsOneWidget);
        expect(find.widgetWithText(Chip, 'old'), findsOneWidget);
      },
    );
  }

  testWidgets('library uses cached artwork and handles missing files offline', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('library_art'),
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
    final repo = MemoryRepository()
      ..data.add(
        tab().copyWith(artwork: jsonEncode({'local_path': file.path})),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlbumArt), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.runAsync(() => file.delete());
    repo.data[0] = tab().copyWith(
      artwork: jsonEncode({'local_path': '${dir.path}/missing.png'}),
    );
    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.album_outlined), findsOneWidget);
  });
  testWidgets('library load and deletion failures offer recovery', (
    tester,
  ) async {
    final repo = MemoryRepository()
      ..data.add(tab())
      ..failLoad = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load your library'), findsOneWidget);
    repo.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Offline song'), findsOneWidget);
    repo.failDelete = true;
    await tester.tap(find.byTooltip('Tab options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not delete tab'), findsOneWidget);
    expect(repo.data, hasLength(1));
    repo.failDelete = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(repo.data, isEmpty);
  });
  testWidgets('practice library error can be retried', (tester) async {
    final repo = MemoryRepository()
      ..data.add(tab())
      ..failLoad = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PracticeScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load your library'), findsOneWidget);
    repo.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Offline song'), findsOneWidget);
  });
  testWidgets('filter dialog works with large text on a small screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repo = MemoryRepository()..data.add(tab());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.widgetWithText(TextField, 'Tags'));
    await tester.enterText(find.widgetWithText(TextField, 'Tags'), 'jazz');
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(repo.lastFilter.tags, {'jazz'});
    expect(repo.lastFilter.instrument, InstrumentType.bass);
    expect(repo.lastFilter.classification, InstrumentClassification.electric);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed import offers file picker recovery', (tester) async {
    final previous = FilePickerPlatform.instance;
    final picker = FailingPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryScreen(repository: MemoryRepository())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import Tab'));
    await tester.pumpAndSettle();
    expect(find.text('Could not import this file.'), findsOneWidget);
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(picker.calls, 2);
  });
}
