import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/database/sqlite_tab_repository.dart';
import 'package:riffshelf/core/database/tab_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SavedTab example({
  String ascii = 'E|--0--',
  List<TabMeasure> measures = const [],
}) => SavedTab(
  title: 'Song',
  artist: 'Artist',
  source: 'Local',
  sourceUrl: '',
  instrument: InstrumentType.bass,
  classification: InstrumentClassification.electric,
  stringCount: 5,
  tuning: const ['B', 'E', 'A', 'D', 'G'],
  trackName: 'Bass',
  bpm: 120,
  tags: const ['rock'],
  asciiTab: ascii,
  measures: measures,
  isFavorite: true,
  albumArt: 'cover.jpg',
  sourceData: '{"key":"value"}',
);

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory directory;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('riffshelf_test_');
    path = '${directory.path}/library.db';
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('ASCII and timed structured data serialize without losing details', () {
    final tab = example(
      measures: const [
        TabMeasure(
          number: 1,
          numerator: 3,
          beats: [
            TabBeat(
              position: 0,
              duration: 0.5,
              notes: [
                TabNote(
                  stringNumber: 5,
                  fret: 3,
                  duration: 0.5,
                  technique: 'slide',
                ),
              ],
            ),
            TabBeat(position: 0.5, duration: 1, isRest: true),
          ],
        ),
      ],
    );
    final restored = SavedTab.fromDatabaseMap(tab.toDatabaseMap());
    expect(restored.instrument, InstrumentType.bass);
    expect(restored.classification, InstrumentClassification.electric);
    expect(restored.tuning, ['B', 'E', 'A', 'D', 'G']);
    expect(restored.stringCount, 5);
    expect(restored.asciiTab, tab.asciiTab);
    expect(restored.measures.first.beats.last.isRest, isTrue);
    expect(restored.measures.first.beats.first.notes.single.fret, 3);
    expect(restored.measures.first.beats.first.notes.single.duration, 0.5);
    expect(
      jsonEncode(restored.toDatabaseMap()),
      jsonEncode(tab.toDatabaseMap()),
    );
    final guitar = SavedTab(
      title: 'Guitar',
      artist: 'A',
      source: 'Local',
      sourceUrl: '',
      instrument: InstrumentType.guitar,
      classification: InstrumentClassification.acoustic,
      stringCount: 6,
      tuning: const ['D', 'A', 'D', 'G', 'B', 'E'],
      measures: tab.measures,
    );
    expect(
      SavedTab.fromDatabaseMap(guitar.toDatabaseMap()).classification,
      InstrumentClassification.acoustic,
    );
    expect(guitar.hasUsableContent, isTrue);
  });

  test('persists, filters, updates, deletes and reopens', () async {
    var repo = SqliteTabRepository(factory, path);
    final saved = await repo.save(example());
    await expectLater(repo.save(example(ascii: '  ')), throwsArgumentError);
    await repo.close();
    repo = SqliteTabRepository(factory, path);
    final loaded = (await repo.getById(saved.id!))!;
    expect(loaded.albumArt, 'cover.jpg');
    expect(loaded.sourceData, '{"key":"value"}');
    expect(
      (await repo.findTabs(
        const TabFilter(
          query: 'SON',
          instrument: InstrumentType.bass,
          tuning: ['b', 'e', 'a', 'd', 'g'],
          tags: {'rock'},
          favoritesOnly: true,
        ),
      )),
      hasLength(1),
    );
    expect(await repo.allTags(), {'rock'});
    await repo.save(loaded.copyWith(isFavorite: false, tags: ['jazz']));
    expect(await repo.findTabs(const TabFilter(favoritesOnly: true)), isEmpty);
    expect(await repo.allTags(), {'jazz'});
    await repo.delete(saved.id!);
    expect(await repo.getById(saved.id!), isNull);
    await repo.close();
  });

  test('migrates a version 1 library and retains its data', () async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            '''CREATE TABLE saved_tabs (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, artist TEXT NOT NULL, source TEXT NOT NULL, source_url TEXT NOT NULL, source_id TEXT, tab_type TEXT NOT NULL, track_name TEXT, instrument TEXT NOT NULL, string_count INTEGER NOT NULL, tuning TEXT NOT NULL, tuning_key TEXT NOT NULL, capo INTEGER NOT NULL, bpm INTEGER, tags TEXT NOT NULL, ascii_tab TEXT NOT NULL, structure TEXT NOT NULL, source_data TEXT)''',
          );
          final data = example().toDatabaseMap()
            ..remove('classification')
            ..remove('is_favorite')
            ..remove('album_art');
          await db.insert('saved_tabs', data);
        },
      ),
    );
    await db.close();
    final repo = SqliteTabRepository(factory, path);
    final tab = (await repo.findTabs()).single;
    expect(tab.asciiTab, 'E|--0--');
    expect(tab.isFavorite, isFalse);
    expect(tab.classification, InstrumentClassification.other);
    await repo.close();
  });
}
