import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:riffshelf/core/database/sqlite_practice_session_repository.dart';
import 'package:riffshelf/core/database/sqlite_tab_repository.dart';
import 'package:riffshelf/core/database/tab_repository.dart';
import 'package:riffshelf/core/models/practice_session.dart';
import 'package:riffshelf/features/import/tab_import_service.dart';
import 'package:sqflite/sqflite.dart';

/// Regression test for storage on a real device.
///
/// Unit tests use the desktop FFI build of SQLite. This runs the same import
/// and repository code against the platform's native SQLite on Android and
/// iOS. It uses its own database file, so the app's library is not touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const asciiTab = '''
e|-----0-----|
B|---1---1---|
G|-2-------2-|
D|-----------|
A|-----------|
E|-----------|
''';

  late String path;

  setUp(() async {
    path = p.join(
      await databaseFactory.getDatabasesPath(),
      'riffshelf_it_${DateTime.now().microsecondsSinceEpoch}.db',
    );
  });

  tearDown(() => databaseFactory.deleteDatabase(path));

  testWidgets('imports, saves, finds, and deletes a text tab', (_) async {
    const importer = TabImportService();
    final bytes = Uint8List.fromList(utf8.encode(asciiTab));
    final parsed = importer.parseText(bytes, 'Device Test.txt');
    final imported = parsed.copyWith(importKey: importer.importKey(bytes, 0));
    expect(imported.title, 'Device Test');
    expect(imported.stringCount, 6);

    final repository = SqliteTabRepository(databaseFactory, path);
    addTearDown(repository.close);

    final saved = await repository.save(imported);
    expect(saved.id, isNotNull);
    await expectLater(
      repository.save(imported),
      throwsA(isA<DuplicateTabException>()),
    );

    final found = await repository.findTabs(
      const TabFilter(query: 'device test'),
    );
    expect(found.map((tab) => tab.id), [saved.id]);
    expect(found.single.asciiTab, asciiTab);

    await repository.delete(saved.id!);
    expect(await repository.getById(saved.id!), isNull);
  });

  testWidgets('keeps tabs and practice history after reopening', (_) async {
    const importer = TabImportService();
    final bytes = Uint8List.fromList(utf8.encode(asciiTab));
    final parsed = importer.parseText(bytes, 'Reopen.txt');
    var tabs = SqliteTabRepository(databaseFactory, path);
    final saved = await tabs.save(
      parsed.copyWith(isFavorite: true, tags: ['regression']),
    );
    await SqlitePracticeSessionRepository(tabs).save(
      PracticeSession(
        title: saved.title,
        artist: saved.artist,
        savedAt: DateTime.utc(2026, 11, 20, 12),
        durationMilliseconds: 90000,
        startMeasure: 1,
        endMeasure: 1,
        markedComplete: true,
        confirmedNotes: 5,
      ),
    );
    await tabs.close();

    tabs = SqliteTabRepository(databaseFactory, path);
    addTearDown(tabs.close);

    final reopened = await tabs.getById(saved.id!);
    expect(reopened, isNotNull);
    expect(reopened!.isFavorite, isTrue);
    expect(reopened.tags, ['regression']);
    expect(await tabs.allTags(), {'regression'});

    final history = await SqlitePracticeSessionRepository(tabs).getAll();
    expect(history, hasLength(1));
    expect(history.single.durationMilliseconds, 90000);
    expect(history.single.markedComplete, isTrue);
    expect(PracticeHistorySummary(history).completedSections, 1);
  });
}
