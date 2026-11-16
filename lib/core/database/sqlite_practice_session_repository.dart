import 'package:sqflite/sqflite.dart';

import '../models/practice_session.dart';
import 'practice_session_repository.dart';
import 'sqlite_tab_repository.dart';

class SqlitePracticeSessionRepository implements PracticeSessionRepository {
  SqlitePracticeSessionRepository(this._tabs);

  factory SqlitePracticeSessionRepository.local() =>
      SqlitePracticeSessionRepository(SqliteTabRepository.local());

  final SqliteTabRepository _tabs;

  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS practice_history (
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
  }

  @override
  Future<void> save(PracticeSession session) async {
    await (await _tabs.database).insert(
      'practice_history',
      session.toDatabaseMap(),
    );
  }

  @override
  Future<List<PracticeSession>> getAll() async {
    final rows = await (await _tabs.database).query(
      'practice_history',
      orderBy: 'saved_at DESC, id DESC',
    );
    return rows.map(PracticeSession.fromDatabaseMap).toList();
  }

  @override
  Future<void> clear() async {
    final db = await _tabs.database;
    await db.transaction((txn) async {
      await txn.delete('practice_history');
      // Earlier unfinished builds used this table; clear it too if present.
      final oldTable = await txn.query(
        'sqlite_master',
        columns: ['name'],
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'practice_sessions'],
      );
      if (oldTable.isNotEmpty) await txn.delete('practice_sessions');
    });
  }
}
