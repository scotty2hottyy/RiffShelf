import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riffshelf/core/database/sqlite_tab_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/features/search/application/tab_search_service.dart';
import 'package:riffshelf/features/search/data/songsterr_provider.dart';
import 'package:riffshelf/features/search/domain/tab_source_provider.dart';

import 'support/songsterr_fixtures.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeProvider implements TabSourceProvider {
  FakeProvider(this.name, {this.fail = false, this.tab});
  @override
  final String name;
  final bool fail;
  final SavedTab? tab;
  @override
  Future<List<TabSearchResult>> search(TabSearchQuery query) async {
    if (fail) throw const TabProviderException('Unavailable');
    return [songsterrResult];
  }

  @override
  Future<SavedTab> fetchTab(TabSearchResult result) async => tab!;
}

void main() {
  setUpAll(sqfliteFfiInit);
  test('normalizes guitar and bass and rejects malformed responses', () {
    final data = jsonEncode([
      {
        'songId': 19,
        'title': 'Song',
        'artist': 'Artist',
        'tracks': [
          {'instrument': 'Guitar'},
          {'instrument': 'Bass'},
        ],
      },
    ]);
    final results = SongsterrProvider.parseSearchResponse(data);
    expect(results.map((r) => r.instrument), [
      InstrumentType.guitar,
      InstrumentType.bass,
    ]);
    expect(results.first.sourceName, 'Songsterr');
    expect(
      () => SongsterrProvider.parseSearchResponse('{}'),
      throwsA(isA<TabProviderException>()),
    );
  });
  test('aggregates partial provider failures', () async {
    final response = await TabSearchService([
      FakeProvider('ok'),
      FakeProvider('bad', fail: true),
    ]).search(const TabSearchQuery(text: 'song'));
    expect(response.results, hasLength(1));
    expect(response.failures.single.provider, 'bad');
  });
  test('provider times out and filters instruments', () async {
    final provider = SongsterrProvider(
      client: MockClient(
        (_) => Future.delayed(
          const Duration(milliseconds: 100),
          () => http.Response('[]', 200),
        ),
      ),
      timeout: const Duration(milliseconds: 5),
    );
    await expectLater(
      provider.search(const TabSearchQuery(text: 'song')),
      throwsA(isA<TabProviderException>()),
    );
    final filtered = SongsterrProvider(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'id': 1,
              'title': 'Song',
              'artist': 'Artist',
              'tracks': [
                {'instrument': 'Guitar'},
                {'instrument': 'Bass'},
              ],
            },
          ]),
          200,
        ),
      ),
    );
    final results = await filtered.search(
      const TabSearchQuery(text: 'song', instrument: InstrumentType.bass),
    );
    expect(results.single.instrument, InstrumentType.bass);
  });
  test(
    'fetches selected real structured track from mocked responses',
    () async {
      final provider = SongsterrProvider(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/revisions')) {
            return http.Response('[]', 200);
          }
          if (request.url.path == '/api/meta/19') {
            return http.Response(jsonEncode(currentSongMetadata()), 200);
          }
          return http.Response(jsonEncode(currentTrackPayload()), 200);
        }),
      );
      final tab = await TabSearchService([provider]).fetch(songsterrResult);
      expect(tab.trackName, 'Lead Guitar');
      expect(tab.measures.first.beats.first.notes.single.fret, 2);
      expect(tab.importKey, isNotNull);
    },
  );
  test('rejects empty content', () async {
    final tab = SavedTab(
      title: 'x',
      artist: 'y',
      source: 'ok',
      sourceUrl: '',
      instrument: InstrumentType.guitar,
      stringCount: 6,
      tuning: const ['E', 'A', 'D', 'G', 'B', 'E'],
    );
    final result = TabSearchResult(
      externalId: '1',
      title: 'x',
      artist: 'y',
      instrument: InstrumentType.guitar,
      sourceName: 'ok',
      sourceUrl: '',
    );
    await expectLater(
      TabSearchService([FakeProvider('ok', tab: tab)]).fetch(result),
      throwsA(isA<TabProviderException>()),
    );
  });
  test('downloaded track persists and reopens from SQLite', () async {
    final provider = SongsterrProvider(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/revisions')) {
          return http.Response('[]', 200);
        }
        if (request.url.path == '/api/meta/19') {
          return http.Response(jsonEncode(currentSongMetadata()), 200);
        }
        return http.Response(jsonEncode(currentTrackPayload()), 200);
      }),
    );
    final repository = SqliteTabRepository(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    final tab = await TabSearchService([provider]).fetch(songsterrResult);
    final saved = await repository.save(tab);
    final restored = await repository.getById(saved.id!);
    expect(restored!.trackName, 'Lead Guitar');
    expect(restored.measures.first.beats.first.notes.single.fret, 2);
    await repository.close();
  });
}
