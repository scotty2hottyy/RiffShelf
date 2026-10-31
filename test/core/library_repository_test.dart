import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/database/sqlite_tab_repository.dart';
import 'package:riffshelf/core/database/tab_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SavedTab makeTab({
  String key = 'file-a:0',
  String title = 'Same title',
  InstrumentType instrument = InstrumentType.bass,
  InstrumentClassification classification = InstrumentClassification.electric,
  List<String> tuning = const ['B', 'E', 'A', 'D', 'G'],
  List<String> tags = const ['Rock', 'Live'],
}) => SavedTab(
  title: title,
  artist: 'Example Artist',
  source: 'Local',
  sourceUrl: 'original.gp5',
  sourceId: 'original.gp5',
  importKey: key,
  instrument: instrument,
  classification: classification,
  stringCount: tuning.length,
  tuning: tuning,
  tags: tags,
  asciiTab: 'G|--3--|\nD|--0--|',
  measures: const [
    TabMeasure(
      number: 1,
      beats: [
        TabBeat(
          position: 1.5,
          duration: 0.5,
          notes: [TabNote(stringNumber: 1, fret: 3, duration: 0.5)],
        ),
      ],
    ),
  ],
);

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('riffshelf_library_');
    path = '${directory.path}/tabs.db';
  });
  tearDown(() async => directory.delete(recursive: true));
  test('duplicate key rejects repeat but preserves distinct arrangements with the same title', () async {
    final repo = SqliteTabRepository(databaseFactoryFfi, path);
    await repo.save(makeTab());
    await expectLater(
      repo.save(makeTab()),
      throwsA(isA<DuplicateTabException>()),
    );
    await repo.save(makeTab(key: 'file-a:1'));
    await repo.save(makeTab(key: 'different-file:0'));
    expect(await repo.findTabs(), hasLength(3));
    await repo.close();
  });
  test('combined filters, searches and edits survive reopening without changing content', () async {
    var repo = SqliteTabRepository(databaseFactoryFfi, path);
    final saved = await repo.save(makeTab());
    await repo.save(
      makeTab(
        key: 'guitar:0',
        title: 'Other song',
        instrument: InstrumentType.guitar,
        classification: InstrumentClassification.acoustic,
        tuning: ['E', 'A', 'D', 'G', 'B', 'E'],
      ),
    );
    await repo.save(
      makeTab(
        key: 'unknown:0',
        title: 'Unknown',
        instrument: InstrumentType.other,
        classification: InstrumentClassification.other,
        tuning: ['?', '?', '?', '?'],
      ),
    );
    final edited = saved
        .withMetadata(
          title: saved.title,
          artist: saved.artist,
          instrument: saved.instrument,
          classification: saved.classification,
          tuning: ['B1', 'E2', 'A2', 'D3', 'G3'],
          capo: saved.capo,
          bpm: saved.bpm,
          tags: ['Jazz', 'Live'],
          trackName: saved.trackName,
        )
        .copyWith(isFavorite: true);
    await repo.save(edited);
    await repo.close();
    repo = SqliteTabRepository(databaseFactoryFfi, path);
    final loaded = (await repo.getById(saved.id!))!;
    expect(loaded.isFavorite, isTrue);
    expect(loaded.tags, ['Jazz', 'Live']);
    expect(loaded.tuning, ['B1', 'E2', 'A2', 'D3', 'G3']);
    expect(loaded.sourceUrl, saved.sourceUrl);
    expect(loaded.importKey, saved.importKey);
    expect(loaded.asciiTab, saved.asciiTab);
    expect(loaded.measures.single.beats.single.position, 1.5);
    expect(loaded.measures.single.beats.single.notes.single.duration, 0.5);
    final filter = TabFilter(
      query: 'ARTIST',
      instrument: InstrumentType.bass,
      classification: InstrumentClassification.electric,
      stringCount: 5,
      tuning: const ['b1', 'e2', 'a2', 'd3', 'g3'],
      tags: const {'jazz', 'LIVE'},
      favoritesOnly: true,
    );
    expect(await repo.findTabs(filter), hasLength(1));
    expect(
      await repo.findTabs(const TabFilter(query: 'same title')),
      hasLength(1),
    );
    expect(
      await repo.findTabs(
        const TabFilter(
          instrument: InstrumentType.guitar,
          classification: InstrumentClassification.acoustic,
          stringCount: 6,
        ),
      ),
      hasLength(1),
    );
    expect(
      await repo.findTabs(
        const TabFilter(
          instrument: InstrumentType.other,
          classification: InstrumentClassification.other,
          stringCount: 4,
        ),
      ),
      hasLength(1),
    );
    expect(
      await repo.findTabs(
        const TabFilter(
          instrument: InstrumentType.bass,
          classification: InstrumentClassification.acoustic,
        ),
      ),
      isEmpty,
    );
    await repo.delete(saved.id!);
    await repo.close();
    repo = SqliteTabRepository(databaseFactoryFfi, path);
    expect(await repo.getById(saved.id!), isNull);
    await repo.close();
  });
}
