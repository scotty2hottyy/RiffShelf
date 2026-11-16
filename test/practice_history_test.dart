import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riffshelf/core/database/sqlite_practice_session_repository.dart';
import 'package:riffshelf/core/database/sqlite_tab_repository.dart';
import 'package:riffshelf/core/models/practice_session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PracticeSession session(String title, int seconds, {bool completed = false}) =>
    PracticeSession(
      title: title,
      artist: 'Artist',
      savedAt: DateTime.utc(2026, 1, 1),
      durationMilliseconds: seconds * 1000,
      startMeasure: 2,
      endMeasure: 4,
      markedComplete: completed,
      confirmedNotes: 3,
    );

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('riffshelf_history_');
    path = p.join(directory.path, 'tabs.db');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('saved sessions survive reopening, aggregate and clear', () async {
    var tabs = SqliteTabRepository(databaseFactoryFfi, path);
    var history = SqlitePracticeSessionRepository(tabs);
    await history.save(session('First', 70, completed: true));
    await history.save(session('Second', 30));
    await tabs.close();

    tabs = SqliteTabRepository(databaseFactoryFfi, path);
    history = SqlitePracticeSessionRepository(tabs);
    final loaded = await history.getAll();
    expect(loaded.map((s) => s.title), ['Second', 'First']);
    expect(loaded.last.startMeasure, 2);
    expect(loaded.last.endMeasure, 4);
    expect(loaded.last.markedComplete, isTrue);
    final summary = PracticeHistorySummary(loaded);
    expect(summary.sessions, 2);
    expect(summary.durationMilliseconds, 100000);
    expect(summary.completedSections, 1);
    expect(summary.confirmedNotes, 6);
    await history.clear();
    await tabs.close();

    tabs = SqliteTabRepository(databaseFactoryFfi, path);
    expect(await SqlitePracticeSessionRepository(tabs).getAll(), isEmpty);
    await tabs.close();
  });

  for (final oldVersion in [4, 5]) {
    test('upgrades version $oldVersion and preserves existing data', () async {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: oldVersion,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE saved_tabs (id INTEGER PRIMARY KEY)',
            );
            await db.insert('saved_tabs', {'id': 42});
            await db.execute('CREATE TABLE practice_sessions (id INTEGER)');
            await db.insert('practice_sessions', {'id': 1});
          },
        ),
      );
      await old.close();
      final tabs = SqliteTabRepository(databaseFactoryFfi, path);
      final history = SqlitePracticeSessionRepository(tabs);
      await history.save(session('After upgrade', 5));
      expect(await history.getAll(), hasLength(1));
      await history.clear();
      final db = await tabs.database;
      expect(await db.query('saved_tabs'), hasLength(1));
      expect(await db.query('practice_sessions'), isEmpty);
      await tabs.close();
    });
  }
}
