import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/saved_tab.dart';
import '../models/tuning.dart';
import 'tab_repository.dart';

class SqliteTabRepository implements TabRepository {
  SqliteTabRepository(this._databaseFactory, [this._databasePath]);

  static final ValueNotifier<int> changes = ValueNotifier(0);

  factory SqliteTabRepository.local() => SqliteTabRepository(databaseFactory);

  final DatabaseFactory _databaseFactory;
  final String? _databasePath;
  Database? _database;
  Future<Database>? _opening;

  Future<Database> get _db => _opening ??= _open();

  Future<Database> _open() async {
    final path =
        _databasePath ??
        p.join(await _databaseFactory.getDatabasesPath(), 'riffshelf.db');
    return _database ??= await _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE saved_tabs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            source TEXT NOT NULL,
            source_url TEXT NOT NULL,
            source_id TEXT,
            import_key TEXT,
            tab_type TEXT NOT NULL DEFAULT 'tab',
            track_name TEXT,
            instrument TEXT NOT NULL,
            string_count INTEGER NOT NULL,
            tuning TEXT NOT NULL,
            tuning_key TEXT NOT NULL,
            capo INTEGER NOT NULL DEFAULT 0,
            bpm INTEGER,
            tags TEXT NOT NULL,
            ascii_tab TEXT NOT NULL,
            structure TEXT NOT NULL,
            source_data TEXT,
            classification TEXT NOT NULL DEFAULT 'other',
            is_favorite INTEGER NOT NULL DEFAULT 0,
            album_art TEXT
          )
        ''');
          await db.execute(
            'CREATE INDEX saved_tabs_title ON saved_tabs(title)',
          );
          await db.execute(
            'CREATE INDEX saved_tabs_artist ON saved_tabs(artist)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX saved_tabs_import_key ON saved_tabs(import_key)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE saved_tabs ADD COLUMN classification TEXT NOT NULL DEFAULT 'other'",
            );
            await db.execute(
              'ALTER TABLE saved_tabs ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE saved_tabs ADD COLUMN album_art TEXT',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE saved_tabs ADD COLUMN import_key TEXT',
            );
            await db.execute(
              'CREATE UNIQUE INDEX saved_tabs_import_key ON saved_tabs(import_key)',
            );
          }
        },
      ),
    );
  }

  @override
  Future<List<SavedTab>> findTabs([
    TabFilter filter = const TabFilter(),
  ]) async {
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (filter.query.trim().isNotEmpty) {
      clauses.add(
        '(title LIKE ? COLLATE NOCASE OR artist LIKE ? COLLATE NOCASE)',
      );
      final pattern = '%${filter.query.trim()}%';
      arguments.addAll([pattern, pattern]);
    }
    if (filter.favoritesOnly) {
      clauses.add('is_favorite = 1');
    }
    if (filter.instrument != null) {
      clauses.add('instrument = ?');
      arguments.add(filter.instrument!.name);
    }
    if (filter.classification != null) {
      clauses.add('classification = ?');
      arguments.add(filter.classification!.name);
    }
    if (filter.stringCount != null) {
      clauses.add('string_count = ?');
      arguments.add(filter.stringCount!);
    }
    if (filter.tuning != null) {
      clauses.add('tuning_key = ?');
      arguments.add(StandardTunings.keyFor(filter.tuning!));
    }
    final rows = await (await _db).query(
      'saved_tabs',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'artist COLLATE NOCASE, title COLLATE NOCASE',
    );
    final tabs = rows.map(SavedTab.fromDatabaseMap).toList();
    if (filter.tags.isEmpty) return tabs;
    return tabs.where((tab) {
      final normalized = tab.tags.map((tag) => tag.toLowerCase()).toSet();
      return filter.tags.every((tag) => normalized.contains(tag.toLowerCase()));
    }).toList();
  }

  @override
  Future<SavedTab?> getById(int id) async {
    final rows = await (await _db).query(
      'saved_tabs',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : SavedTab.fromDatabaseMap(rows.single);
  }

  @override
  Future<SavedTab> save(SavedTab tab) async {
    if (!tab.hasUsableContent) {
      throw ArgumentError('Tablature content must not be empty');
    }
    final db = await _db;
    if (tab.id != null) {
      final count = await db.update(
        'saved_tabs',
        tab.toDatabaseMap()..remove('id'),
        where: 'id = ?',
        whereArgs: [tab.id],
      );
      if (count == 0) throw StateError('Tab does not exist: ${tab.id}');
      return tab;
    }
    try {
      final id = await db.insert('saved_tabs', tab.toDatabaseMap());
      changes.value++;
      return tab.copyWith(id: id);
    } on DatabaseException catch (error) {
      if (tab.importKey != null && error.isUniqueConstraintError()) {
        throw const DuplicateTabException();
      }
      rethrow;
    }
  }

  @override
  Future<Set<String>> allTags() async {
    final rows = await (await _db).query('saved_tabs', columns: ['tags']);
    return rows
        .expand(
          (row) => (jsonDecode(row['tags']! as String) as List<Object?>)
              .whereType<String>(),
        )
        .toSet();
  }

  @override
  Future<void> delete(int id) async {
    await (await _db).delete('saved_tabs', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> close() async {
    if (_opening != null) await _opening;
    await _database?.close();
    _database = null;
    _opening = null;
  }
}
