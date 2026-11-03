import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riffshelf/core/database/sqlite_tab_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/features/search/application/tab_search_service.dart';
import 'package:riffshelf/features/search/data/backend_tab_search_client.dart';
import 'package:riffshelf/features/search/data/songsterr_provider.dart';
import 'package:riffshelf/features/search/domain/tab_source_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/songsterr_fixtures.dart';

final apiResults = jsonEncode({
  'results': [
    {
      'artist': 'Metallica',
      'title': 'Enter Sandman',
      'source': 'Songsterr',
      'source_id': '19',
      'source_url': 'https://www.songsterr.com/a/wsa/song?id=19',
      'instrument': 'guitar',
      'available_arrangements': [
        {
          'name': 'Lead Guitar',
          'tuning': ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
        },
        {'name': null, 'tuning': null},
      ],
      'tuning': null,
    },
    {
      'artist': 'Metallica',
      'title': 'Enter Sandman',
      'source': 'Songsterr',
      'source_id': '19',
      'source_url': 'https://www.songsterr.com/a/wsa/song?id=19',
      'instrument': 'bass',
      'available_arrangements': [
        {
          'name': 'Bass',
          'tuning': ['G1', 'C2', 'F2', 'A#2'],
        },
      ],
      'tuning': ['G1', 'C2', 'F2', 'A#2'],
    },
  ],
});

BackendTabSearchClient backend(http.Client client, {Duration? timeout}) =>
    BackendTabSearchClient(
      baseUrl: 'https://api.example.test',
      client: client,
      timeout: timeout ?? const Duration(seconds: 1),
    );

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'requests encoded query and maps arrangements and unknown metadata',
    () async {
      final client = backend(
        MockClient((request) async {
          expect(request.url.scheme, 'https');
          expect(request.url.path, '/api/v1/search/tabs');
          expect(request.url.queryParameters['q'], 'Enter Sandman & More');
          return http.Response(apiResults, 200);
        }),
      );
      final results = await client.search(
        const TabSearchQuery(text: ' Enter Sandman & More '),
      );
      expect(results, hasLength(2));
      final guitar = results.first;
      expect(guitar.externalId, '19');
      expect(guitar.sourceName, 'Songsterr');
      expect(guitar.instrument, InstrumentType.guitar);
      expect(guitar.tuning, isNull);
      expect(guitar.availableArrangements, hasLength(2));
      expect(guitar.availableArrangements.first.name, 'Lead Guitar');
      expect(guitar.availableArrangements.first.tuning, [
        'E2',
        'A2',
        'D3',
        'G3',
        'B3',
        'E4',
      ]);
      expect(guitar.availableArrangements.last.name, isNull);
      expect(guitar.availableArrangements.last.tuning, isNull);
      expect(results.last.instrument, InstrumentType.bass);
      expect(results.last.tuning, ['G1', 'C2', 'F2', 'A#2']);
      expect(results.last.stringCount, 4);
      expect(results.last.type, TabType.other);
    },
  );

  test('empty results and instrument filter', () async {
    final empty = backend(
      MockClient((_) async => http.Response('{"results":[]}', 200)),
    );
    expect(await empty.search(const TabSearchQuery(text: 'missing')), isEmpty);
    final service = TabSearchService(
      [
        SongsterrProvider(
          client: MockClient(
            (_) async => throw StateError('direct search used'),
          ),
        ),
      ],
      searchProvider: backend(
        MockClient((_) async => http.Response(apiResults, 200)),
      ),
    );
    final found = await service.search(
      const TabSearchQuery(text: 'Sandman', instrument: InstrumentType.bass),
    );
    expect(found.failures, isEmpty);
    expect(found.results.single.instrument, InstrumentType.bass);
  });

  test('HTTP and rate limit errors have useful messages', () async {
    for (final entry in {
      429: 'Too many searches',
      502: 'temporarily unavailable',
      504: 'timed out',
      422: 'Enter a song',
      500: 'HTTP 500',
    }.entries) {
      final client = backend(
        MockClient((_) async => http.Response('{}', entry.key)),
      );
      await expectLater(
        client.search(const TabSearchQuery(text: 'Song')),
        throwsA(
          isA<TabProviderException>().having(
            (e) => e.message,
            'message',
            contains(entry.value),
          ),
        ),
      );
    }
  });

  test('timeout, connection error, and invalid JSON', () async {
    final slow = backend(
      MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response(apiResults, 200);
      }),
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      slow.search(const TabSearchQuery(text: 'Song')),
      throwsA(
        isA<TabProviderException>().having(
          (e) => e.kind,
          'kind',
          TabProviderErrorKind.timeout,
        ),
      ),
    );
    final offline = backend(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      offline.search(const TabSearchQuery(text: 'Song')),
      throwsA(
        isA<TabProviderException>().having(
          (e) => e.kind,
          'kind',
          TabProviderErrorKind.network,
        ),
      ),
    );
    for (final body in [
      'not json',
      '{}',
      '{"results":[{"source":"Songsterr"}]}',
    ]) {
      final invalid = backend(
        MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        invalid.search(const TabSearchQuery(text: 'Song')),
        throwsA(
          isA<TabProviderException>().having(
            (e) => e.kind,
            'kind',
            TabProviderErrorKind.malformed,
          ),
        ),
      );
    }
  });

  test('configuration requires HTTPS in production', () async {
    final client = BackendTabSearchClient(
      baseUrl: 'http://api.example.test',
      client: MockClient((_) async => http.Response(apiResults, 200)),
      requireHttps: true,
    );
    await expectLater(
      client.search(const TabSearchQuery(text: 'Song')),
      throwsA(
        isA<TabProviderException>().having(
          (e) => e.message,
          'message',
          contains('HTTPS'),
        ),
      ),
    );
  });

  test('retry repeats backend search without direct fallback', () async {
    var requests = 0;
    final service = TabSearchService(
      [
        SongsterrProvider(
          client: MockClient(
            (_) async => throw StateError('direct search used'),
          ),
        ),
      ],
      searchProvider: backend(
        MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response('{}', 502)
              : http.Response(apiResults, 200);
        }),
      ),
    );
    final first = await service.search(const TabSearchQuery(text: 'Song'));
    expect(first.results, isEmpty);
    expect(
      first.failures.single.error.toString(),
      contains('temporarily unavailable'),
    );
    final retry = await service.search(const TabSearchQuery(text: 'Song'));
    expect(retry.failures, isEmpty);
    expect(retry.results, hasLength(2));
    expect(requests, 2);
  });

  test(
    'backend result downloads through Songsterr and persists in SQLite',
    () async {
      final songsterr = SongsterrProvider(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/revisions')) {
            return http.Response('[]', 200);
          }
          if (request.url.path == '/api/meta/19') {
            return http.Response(
              jsonEncode(currentSongMetadata(multiple: false)),
              200,
            );
          }
          return http.Response(jsonEncode(currentTrackPayload()), 200);
        }),
      );
      final service = TabSearchService(
        [songsterr],
        searchProvider: backend(
          MockClient((_) async => http.Response(apiResults, 200)),
        ),
      );
      final result = (await service.search(
        const TabSearchQuery(text: 'Sandman'),
      )).results.first;
      final tab = await service.fetch(result);
      expect(tab.trackName, 'Lead Guitar');
      expect(tab.measures.first.beats.first.notes.single.fret, 2);
      final repository = SqliteTabRepository(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      final saved = await repository.save(tab);
      final restored = await repository.getById(saved.id!);
      expect(restored!.sourceId, '19');
      expect(restored.measures.first.beats.first.notes.single.fret, 2);
      await repository.close();
    },
  );
}
