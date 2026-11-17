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
      await db.close();
      await tabs.close();
    });
  }

  test(
    'upgrades version 6 practice history to version 7 preserving existing data',
    () async {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE saved_tabs (
              id INTEGER PRIMARY KEY,
              title TEXT,
              artist TEXT,
              source TEXT,
              source_url TEXT,
              instrument TEXT,
              string_count INTEGER,
              tuning TEXT,
              tuning_key TEXT,
              tags TEXT,
              ascii_tab TEXT,
              structure TEXT,
              classification TEXT,
              is_favorite INTEGER
            )
          ''');
            await db.execute('''
            CREATE TABLE practice_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              saved_at TEXT NOT NULL,
              duration_ms INTEGER NOT NULL,
              start_measure INTEGER,
              end_measure INTEGER,
              marked_complete INTEGER NOT NULL,
              confirmed_notes INTEGER NOT NULL
            )
          ''');
            await db.insert('practice_history', {
              'title': 'V6 Legacy Session',
              'artist': 'Legacy Artist',
              'saved_at': DateTime.utc(2025, 12, 1).toIso8601String(),
              'duration_ms': 45000,
              'start_measure': 1,
              'end_measure': 3,
              'marked_complete': 1,
              'confirmed_notes': 12,
            });
          },
        ),
      );
      await old.close();

      final tabs = SqliteTabRepository(databaseFactoryFfi, path);
      final history = SqlitePracticeSessionRepository(tabs);

      final loaded = await history.getAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.title, 'V6 Legacy Session');
      expect(loaded.first.hits, isNull);
      expect(loaded.first.misses, isNull);
      expect(loaded.first.accuracy, isNull);
      expect(loaded.first.confirmedNotes, 12);

      final newSession = PracticeSession(
        title: 'V7 Timed Session',
        artist: 'New Artist',
        savedAt: DateTime.utc(2026, 1, 15),
        durationMilliseconds: 60000,
        startMeasure: 1,
        endMeasure: 4,
        markedComplete: true,
        confirmedNotes: 8,
        hits: 8,
        misses: 2,
        accuracy: 80.0,
      );
      await history.save(newSession);

      final updated = await history.getAll();
      expect(updated, hasLength(2));
      final v7 = updated.firstWhere((s) => s.title == 'V7 Timed Session');
      expect(v7.hits, 8);
      expect(v7.misses, 2);
      expect(v7.accuracy, 80.0);

      final v6 = updated.firstWhere((s) => s.title == 'V6 Legacy Session');
      expect(v6.hits, isNull);
      expect(v6.misses, isNull);

      final summary = PracticeHistorySummary(updated);
      expect(summary.sessions, 2);
      expect(summary.totalHits, 8);
      expect(summary.totalMisses, 2);
      expect(summary.averageAccuracy, 80.0);

      await tabs.close();
    },
  );
}
