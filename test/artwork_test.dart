import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riffshelf/core/database/sqlite_tab_repository.dart';
import 'package:riffshelf/core/database/tab_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/features/artwork/album_art.dart';
import 'package:riffshelf/features/artwork/artwork_service.dart';
import 'package:riffshelf/features/tabs/tab_detail_screen.dart';
import 'package:riffshelf/screens/library_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const id1 = 'a1ed26f7-3f11-4633-a3c7-4a4abfa3271f';
const id2 = 'cb3d57ed-69d6-4f7d-b1bd-1b4975ba6b90';
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaGj4DwADhAIAV8n6LgAAAABJRU5ErkJggg==';

Map<String, Object?> recording({
  String title = 'Song',
  String artist = 'Artist',
  int score = 100,
  List<String> releases = const [id1],
}) => {
  'title': title,
  'score': score,
  'artist-credit': [
    {'name': artist},
  ],
  'releases': [
    for (final id in releases)
      {'id': id, 'title': id == id1 ? 'First' : 'Second', 'date': '2000'},
  ],
};
Map<String, Object?> cover({String url = 'http://archive.org/cover.png'}) => {
  'images': [
    {
      'front': true,
      'approved': true,
      'thumbnails': {'250': 'http://archive.org/small.png', '500': url},
    },
  ],
};
MusicBrainzPacer instantPacer() {
  var now = Duration.zero;
  return MusicBrainzPacer(
    clock: () => now,
    wait: (delay) async {
      now += delay;
    },
  );
}

class MemoryRepo implements TabRepository {
  MemoryRepo(this.tab);
  SavedTab tab;
  bool failSave = false;
  @override
  Future<SavedTab> save(SavedTab value) async {
    if (failSave) throw StateError('Storage unavailable');
    tab = value;
    return value;
  }

  @override
  Future<SavedTab?> getById(int id) async => tab;
  @override
  Future<List<SavedTab>> findTabs([
    TabFilter filter = const TabFilter(),
  ]) async => [tab];
  @override
  Future<Set<String>> allTags() async => {};
  @override
  Future<void> delete(int id) async {}
  @override
  Future<void> close() async {}
}

class AutoMemoryRepo extends MemoryRepo implements AutomaticArtworkRepository {
  AutoMemoryRepo(super.tab);

  @override
  Future<bool> setArtworkIfUnselected({
    required int id,
    required String artist,
    required String title,
    required String artwork,
  }) async {
    if (tab.id != id ||
        tab.artist != artist ||
        tab.title != title ||
        tab.artwork != null ||
        tab.albumArt != null) {
      return false;
    }
    tab = tab.copyWith(artwork: artwork);
    return true;
  }
}

class FakeArtworkService extends ArtworkService {
  @override
  Future<List<AlbumCandidate>> candidates(String artist, String title) async =>
      const [
        AlbumCandidate(id1, 'First', 'Artist', '2000'),
        AlbumCandidate(id2, 'Second', 'Artist', '2001'),
      ];
  @override
  Future<String> select(AlbumCandidate album) async =>
      jsonEncode({'release_id': album.id, 'title': album.title});
}

class FailingArtworkService extends ArtworkService {
  @override
  Future<List<AlbumCandidate>> candidates(String artist, String title) async =>
      throw http.ClientException('offline');
}

class FailingDownloadArtworkService extends FakeArtworkService {
  @override
  Future<String> select(AlbumCandidate album) async =>
      throw const FormatException('Artwork unavailable');
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteTabRepository repo;
  late SavedTab tab;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('artwork_test');
    repo = SqliteTabRepository(databaseFactoryFfi, '${dir.path}/tabs.db');
    tab = await repo.save(
      const SavedTab(
        title: 'Song',
        artist: 'Artist',
        source: 'Local',
        sourceUrl: '',
        instrument: InstrumentType.guitar,
        stringCount: 1,
        tuning: ['E'],
        asciiTab: 'E|--0--',
      ),
    );
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });

  ArtworkService serviceFor(
    http.Response Function(http.Request) handler, {
    MusicBrainzPacer? pacer,
  }) => ArtworkService(
    cacheDirectory: dir,
    pacer: pacer ?? instantPacer(),
    client: MockClient((request) async => handler(request)),
  );

  test('direct MusicBrainz search identifies app, escapes query, and returns release metadata', () async {
    final requests = <http.Request>[];
    final service = serviceFor((request) {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'count': 1,
          'recordings': [recording(title: 'Song (Live)', artist: 'Artist')],
        }),
        200,
      );
    });
    final results = await service.candidates('Artist', 'Song (Live)');
    expect(results.single.id, id1);
    expect(results.single.title, 'First');
    expect(results.single.artist, 'Artist');
    expect(results.single.date, '2000');
    expect(requests.single.url.scheme, 'https');
    expect(requests.single.url.host, 'musicbrainz.org');
    expect(requests.single.url.path, '/ws/2/recording/');
    expect(
      requests.single.url.queryParameters['query'],
      contains(r'recording:"Song \(Live\)"'),
    );
    expect(requests.single.headers['User-Agent'], ArtworkService.userAgent);
  });

  test('automatic matching ranks multiple and incomplete results', () async {
    Future<AlbumCandidate?> match(List<Object> recordings, int count) =>
        serviceFor(
          (_) => http.Response(
            jsonEncode({'count': count, 'recordings': recordings}),
            200,
          ),
        ).automaticCandidate('Artist', 'Song');
    expect(
      (await match([
        recording(releases: [id1, id2]),
      ], 1))!.id,
      id1,
    );
    expect((await match([recording()], 101))!.id, id1);
    expect(await match([recording(artist: 'Another')], 1), isNull);
    expect(await match([recording(title: 'Different', score: 50)], 1), isNull);
  });

  test('empty release dates remain selectable as unknown', () async {
    for (final date in ['', '  \t ']) {
      final result = recording();
      result['releases'] = [
        {'id': id1, 'title': 'First', 'date': date},
      ];
      final service = serviceFor(
        (_) => http.Response(
          jsonEncode({
            'count': 1,
            'recordings': [result],
          }),
          200,
        ),
      );
      expect((await service.candidates('Artist', 'Song')).single.date, isNull);
      expect((await service.automaticCandidate('Artist', 'Song'))!.id, id1);
    }
  });

  test(
    'Iron Man ranks the original studio album before reissues and collections',
    () async {
      final ironMan = recording(title: 'Iron Man', artist: 'Black Sabbath');
      ironMan['releases'] = [
        {
          'id': '00000000-0000-0000-0000-000000000003',
          'title': 'Greatest Hits',
          'date': '1977',
          'release-group': {
            'id': 'compilation',
            'primary-type': 'Album',
            'secondary-types': ['Compilation'],
          },
        },
        {
          'id': id2,
          'title': 'Paranoid',
          'date': '2016',
          'release-group': {
            'id': 'paranoid',
            'primary-type': 'Album',
            'first-release-date': '1970-09-18',
          },
        },
        {
          'id': '00000000-0000-0000-0000-000000000004',
          'title': 'Live Evil',
          'date': '1982',
          'release-group': {
            'id': 'live',
            'primary-type': 'Album',
            'secondary-types': ['Live'],
          },
        },
        {
          'id': id1,
          'title': 'Paranoid',
          'date': '1970-09-18',
          'release-group': {
            'id': 'paranoid',
            'primary-type': 'Album',
            'first-release-date': '1970-09-18',
          },
        },
      ];
      final service = serviceFor(
        (_) => http.Response(
          jsonEncode({
            'count': 152,
            'recordings': [ironMan],
          }),
          200,
        ),
      );
      final albums = await service.candidates('Black Sabbath', 'Iron Man');
      expect(albums.map((album) => album.id).toList(), [
        id1,
        id2,
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000004',
      ]);
      expect(
        (await service.automaticCandidate('Black Sabbath', 'Iron Man'))!.id,
        id1,
      );
    },
  );

  test(
    'automatic artwork falls back when the preferred release has no cover',
    () async {
      final requests = <Uri>[];
      final service = serviceFor((request) {
        requests.add(request.url);
        if (request.url.host == 'musicbrainz.org') {
          return http.Response(
            jsonEncode({
              'count': 1,
              'recordings': [
                recording(releases: [id1, id2]),
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'coverartarchive.org') {
          return request.url.path.endsWith(id1)
              ? http.Response('', 404)
              : http.Response(jsonEncode(cover()), 200);
        }
        return http.Response.bytes(
          base64Decode(png),
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      await Future.wait([
        service.assignAutomatically(repo, tab),
        service.assignAutomatically(repo, tab),
      ]);
      final saved = (await repo.getById(tab.id!))!;
      expect(artworkMetadata(saved)!['release_id'], id2);
      expect(
        await File(artworkMetadata(saved)!['local_path'] as String).exists(),
        isTrue,
      );
      expect(
        requests.where((uri) => uri.host == 'musicbrainz.org'),
        hasLength(1),
      );
      expect(requests.where((uri) => uri.path.endsWith(id1)), hasLength(1));
      expect(requests.where((uri) => uri.path.endsWith(id2)), hasLength(1));
    },
  );

  test('fallback limits editions per group and total cover requests', () async {
    final song = recording();
    song['releases'] = [
      for (var i = 0; i < 12; i++)
        {
          'id': '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
          'title': 'Album $i',
          'date': '2000',
          'release-group': {
            'id': i < 4 ? 'same-group' : 'group-$i',
            'primary-type': 'Album',
          },
        },
    ];
    final covers = <String>[];
    final service = serviceFor((request) {
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(
          jsonEncode({
            'count': 1,
            'recordings': [song],
          }),
          200,
        );
      }
      covers.add(request.url.path);
      return http.Response('', 404);
    });
    await service.assignAutomatically(repo, tab);
    expect(covers, hasLength(8));
    expect(covers.any((path) => path.endsWith('000000000002')), isFalse);
    expect(covers.any((path) => path.endsWith('000000000003')), isFalse);
    expect((await repo.getById(tab.id!))!.artwork, isNull);
    await service.assignAutomatically(repo, tab);
    expect(covers, hasLength(8));
  });

  test(
    'malformed releases are skipped while valid releases remain selectable',
    () async {
      final malformed = <Object?>[
        null,
        {'id': 'invalid', 'title': 'Bad'},
        {'id': id2, 'title': ''},
        {'id': id2, 'title': 'Bad', 'date': 2000},
        {'id': id2, 'title': 'Bad', 'date': 'not a date'},
        {'id': id2, 'title': 'Bad', 'artist-credit': []},
      ];
      for (final badRelease in malformed) {
        final result = recording();
        result['releases'] = [
          {'id': id1, 'title': 'First', 'date': '2000'},
          badRelease,
        ];
        var artworkRequests = 0;
        final service = serviceFor((request) {
          if (request.url.host != 'musicbrainz.org') artworkRequests++;
          return http.Response(
            jsonEncode({
              'count': 1,
              'recordings': [result],
            }),
            200,
          );
        });
        expect((await service.candidates('Artist', 'Song')).single.id, id1);
        expect((await service.automaticCandidate('Artist', 'Song'))!.id, id1);
        expect(artworkRequests, 0);
      }
    },
  );

  test(
    'pacer serializes simultaneous calls and respects provider backoff',
    () async {
      var now = Duration.zero;
      final starts = <Duration>[];
      final pacer = MusicBrainzPacer(
        clock: () => now,
        wait: (delay) async {
          now += delay;
        },
      );
      await Future.wait(
        List.generate(
          3,
          (_) => pacer.run(() async {
            starts.add(now);
          }),
        ),
      );
      expect(starts, [
        Duration.zero,
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      pacer.backOff(const Duration(seconds: 5));
      await pacer.run(() async => starts.add(now));
      expect(starts.last, const Duration(seconds: 7));
    },
  );

  test(
    'MusicBrainz rate limit backs off and does not silently retry',
    () async {
      var now = Duration.zero;
      final starts = <Duration>[];
      final pacer = MusicBrainzPacer(
        clock: () => now,
        wait: (delay) async {
          now += delay;
        },
      );
      final service = serviceFor((_) {
        starts.add(now);
        return starts.length == 1
            ? http.Response('', 503, headers: {'retry-after': '3'})
            : http.Response(jsonEncode({'count': 0, 'recordings': []}), 200);
      }, pacer: pacer);
      await expectLater(
        service.candidates('Artist', 'Song'),
        throwsA(isA<ArtworkLookupException>()),
      );
      expect(starts, hasLength(1));
      expect(await service.candidates('Artist', 'Song'), isEmpty);
      expect(starts[1], const Duration(seconds: 3));
    },
  );

  test('new high-confidence saved tab receives locally cached artwork without losing edits', () async {
    final requests = <Uri>[];
    final service = serviceFor((request) {
      requests.add(request.url);
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(
          jsonEncode({
            'count': 1,
            'recordings': [recording()],
          }),
          200,
        );
      }
      if (request.url.host == 'coverartarchive.org') {
        return http.Response(jsonEncode(cover()), 200);
      }
      return http.Response.bytes(
        base64Decode(png),
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    await repo.save(tab.copyWith(tags: ['kept'], isFavorite: true));
    await service.assignAutomatically(repo, tab);
    final saved = (await repo.getById(tab.id!))!;
    final metadata = artworkMetadata(saved)!;
    expect(metadata['release_id'], id1);
    expect(metadata['source_url'], 'https://archive.org/cover.png');
    expect(metadata['rights'], isNull);
    expect(metadata['attribution'], isNull);
    expect(await File(metadata['local_path'] as String).exists(), isTrue);
    expect(saved.tags, ['kept']);
    expect(saved.isFavorite, isTrue);
    expect(requests.map((u) => u.host), [
      'musicbrainz.org',
      'coverartarchive.org',
      'archive.org',
    ]);
    final cached = jsonDecode(
      await service.select(
        const AlbumCandidate(id1, 'First', 'Artist', '2000'),
      ),
    ) as Map;
    expect(cached['local_path'], metadata['local_path']);
    expect(requests, hasLength(3));
  });

  test(
    'manually selected artwork remains available offline after reopening',
    () async {
      var requests = 0;
      final service = serviceFor((request) {
        requests++;
        if (request.url.host == 'coverartarchive.org') {
          return http.Response(jsonEncode(cover()), 200);
        }
        return http.Response.bytes(
          base64Decode(png),
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final artwork = await service.select(
        const AlbumCandidate(id1, 'First', 'Artist', '2000'),
      );
      final selected = tab.copyWith(artwork: artwork);
      await repo.save(selected);
      final localPath = artworkMetadata(selected)!['local_path'] as String;

      await repo.close();
      repo = SqliteTabRepository(databaseFactoryFfi, '${dir.path}/tabs.db');
      final reopened = (await repo.getById(tab.id!))!;
      expect(reopened.artwork, artwork);
      expect(await File(localPath).exists(), isTrue);

      final offline = ArtworkService(
        cacheDirectory: dir,
        client: MockClient((_) async => throw StateError('Unexpected request')),
      );
      final cached = jsonDecode(
        await offline.select(
          const AlbumCandidate(id1, 'First', 'Artist', '2000'),
        ),
      ) as Map;
      expect(cached['local_path'], localPath);
      expect(requests, 2);
    },
  );

  test('invalid metadata, missing art, and provider failures leave saved tabs untouched', () async {
    var count = 0;
    var payload = {
      'count': 1,
      'recordings': [
        recording(releases: [id1, id2]),
      ],
    };
    final service = serviceFor((request) {
      count++;
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(jsonEncode(payload), 200);
      }
      return http.Response('', 404);
    });
    await service.assignAutomatically(repo, tab);
    expect(count, 3);
    expect((await repo.getById(tab.id!))!.artwork, isNull);
    await service.assignAutomatically(
      repo,
      tab.withMetadata(
        title: 'Song',
        artist: '',
        instrument: tab.instrument,
        tuning: tab.tuning,
        capo: 0,
        bpm: null,
        tags: [],
        trackName: null,
      ),
    );
    expect(count, 3);
    payload = {
      'count': 1,
      'recordings': [recording()],
    };
    await service.assignAutomatically(repo, tab);
    expect((await repo.getById(tab.id!))!.artwork, isNull);
    final failed = serviceFor((_) => throw http.ClientException('offline'));
    await failed.assignAutomatically(repo, tab);
    expect((await repo.getById(tab.id!))!.asciiTab, tab.asciiTab);
  });

  test('automatic match cannot overwrite manual artwork, legacy artwork, or edited metadata', () async {
    final service = serviceFor((request) {
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(
          jsonEncode({
            'count': 1,
            'recordings': [recording()],
          }),
          200,
        );
      }
      if (request.url.host == 'coverartarchive.org') {
        return http.Response(jsonEncode(cover()), 200);
      }
      return http.Response.bytes(
        base64Decode(png),
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    await repo.save(tab.copyWith(artwork: '{"release_id":"manual"}'));
    await service.assignAutomatically(repo, tab);
    expect((await repo.getById(tab.id!))!.artwork, '{"release_id":"manual"}');
    await repo.save(tab.copyWith(clearArtwork: true));
    final edited = tab.withMetadata(
      title: 'Edited',
      artist: tab.artist,
      instrument: tab.instrument,
      tuning: tab.tuning,
      capo: 0,
      bpm: null,
      tags: [],
      trackName: null,
    );
    await repo.save(edited);
    await service.assignAutomatically(repo, tab);
    expect((await repo.getById(tab.id!))!.artwork, isNull);
    expect((await repo.getById(tab.id!))!.title, 'Edited');
    final legacy = SavedTab(
      title: 'Song',
      artist: 'Artist',
      source: 'Local',
      sourceUrl: '',
      instrument: InstrumentType.guitar,
      stringCount: 1,
      tuning: const ['E'],
      asciiTab: 'E|--0--',
      albumArt: 'legacy.jpg',
    );
    final legacySaved = await repo.save(legacy);
    await service.assignAutomatically(repo, legacySaved);
    expect((await repo.getById(legacySaved.id!))!.albumArt, 'legacy.jpg');
    expect((await repo.getById(legacySaved.id!))!.artwork, isNull);
  });

  test('manual cancellation stops in-flight automatic matching', () async {
    final response = Completer<http.Response>();
    final service = ArtworkService(
      cacheDirectory: dir,
      pacer: instantPacer(),
      client: MockClient((_) => response.future),
    );
    final job = service.assignAutomatically(repo, tab);
    await Future<void>.delayed(Duration.zero);
    ArtworkService.cancelAutomatic(tab.id!);
    response.complete(
      http.Response(
        jsonEncode({
          'count': 1,
          'recordings': [recording()],
        }),
        200,
      ),
    );
    await job;
    expect((await repo.getById(tab.id!))!.artwork, isNull);
  });

  test('invalid IDs, unsafe redirects, malformed JSON, and image types are rejected', () async {
    final badId = serviceFor((_) => throw StateError('unexpected request'));
    await expectLater(
      badId.select(const AlbumCandidate('not-a-uuid', 'A', 'B', null)),
      throwsFormatException,
    );
    final unsafe = serviceFor((request) {
      if (request.url.host == 'coverartarchive.org') {
        return http.Response(jsonEncode(cover()), 200);
      }
      return http.Response(
        '',
        302,
        headers: {'location': 'https://evil.example/image'},
      );
    });
    await expectLater(
      unsafe.select(const AlbumCandidate(id1, 'A', 'B', null)),
      throwsFormatException,
    );
    final malformed = serviceFor((_) => http.Response('{bad', 200));
    await expectLater(
      malformed.candidates('Artist', 'Song'),
      throwsFormatException,
    );
    final wrongType = serviceFor(
      (request) => request.url.host == 'coverartarchive.org'
          ? http.Response(jsonEncode(cover()), 200)
          : http.Response.bytes(
              base64Decode(png),
              200,
              headers: {'content-type': 'image/jpeg'},
            ),
    );
    await expectLater(
      wrongType.select(const AlbumCandidate(id1, 'A', 'B', null)),
      throwsFormatException,
    );
    final tooLarge = serviceFor(
      (request) => request.url.host == 'coverartarchive.org'
          ? http.Response(jsonEncode(cover()), 200)
          : http.Response.bytes(
              List.filled(2000001, 0),
              200,
              headers: {'content-type': 'image/png'},
            ),
    );
    await expectLater(
      tooLarge.select(const AlbumCandidate(id1, 'A', 'B', null)),
      throwsFormatException,
    );
  });

  test(
    'CAA trusted HTTP redirects are upgraded to HTTPS; 404 produces no cover',
    () async {
      final seen = <Uri>[];
      final service = serviceFor((request) {
        seen.add(request.url);
        if (request.url.host == 'coverartarchive.org') {
          return http.Response(jsonEncode(cover()), 200);
        }
        if (request.url.path == '/cover.png') {
          return http.Response(
            '',
            307,
            headers: {'location': 'http://ia800001.archive.org/final.png'},
          );
        }
        return http.Response.bytes(
          base64Decode(png),
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final metadata = jsonDecode(
        await service.select(
          const AlbumCandidate(id1, 'First', 'Artist', '2000'),
        ),
      ) as Map;
      expect(metadata['local_path'], isNotNull);
      expect(seen.every((uri) => uri.scheme == 'https'), isTrue);
      final missing = serviceFor((_) => http.Response('', 404));
      final result = jsonDecode(
        await missing.select(
          const AlbumCandidate(id2, 'Second', 'Artist', null),
        ),
      ) as Map;
      expect(result['local_path'], isNull);
    },
  );

  testWidgets(
    'manual correction and removal preserve album selection behavior',
    (tester) async {
      final memory = MemoryRepo(tab);
      await tester.pumpWidget(
        MaterialApp(
          home: TabDetailScreen(
            tab: tab,
            repository: memory,
            artworkService: FakeArtworkService(),
          ),
        ),
      );
      await tester.tap(find.text('Choose album'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Second — Artist'));
      await tester.pumpAndSettle();
      expect(artworkMetadata(memory.tab)!['release_id'], id2);
      await tester.tap(find.text('Change album'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('First — Artist'));
      await tester.pumpAndSettle();
      expect(artworkMetadata(memory.tab)!['release_id'], id1);
      await tester.tap(find.text('Remove album'));
      await tester.pumpAndSettle();
      expect(memory.tab.artwork, ArtworkService.removedArtwork);
    },
  );

  testWidgets(
    'offline lookup and failed download show recovery without losing tab',
    (tester) async {
      final memory = MemoryRepo(tab);
      await tester.pumpWidget(
        MaterialApp(
          home: TabDetailScreen(
            tab: tab,
            repository: memory,
            artworkService: FailingArtworkService(),
          ),
        ),
      );
      await tester.tap(find.text('Choose album'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Check your connection'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('E|--0--'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: TabDetailScreen(
            key: const ValueKey('download'),
            tab: tab,
            repository: memory,
            artworkService: FailingDownloadArtworkService(),
          ),
        ),
      );
      await tester.tap(find.text('Choose album'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('First — Artist'));
      await tester.pumpAndSettle();
      expect(find.textContaining('artwork download failed'), findsOneWidget);
      expect(memory.tab.artwork, isNull);
    },
  );

  testWidgets('missing cached image renders the offline fallback', (
    tester,
  ) async {
    final saved = tab.copyWith(
      artwork: jsonEncode({'local_path': '${dir.path}/missing.img'}),
    );
    await tester.pumpWidget(MaterialApp(home: AlbumArt(tab: saved, size: 48)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.album_outlined), findsOneWidget);
  });

  testWidgets('album storage failure is not reported as a network failure', (
    tester,
  ) async {
    final memory = MemoryRepo(tab)..failSave = true;
    await tester.pumpWidget(
      MaterialApp(
        home: TabDetailScreen(
          tab: tab,
          repository: memory,
          artworkService: FakeArtworkService(),
        ),
      ),
    );
    await tester.tap(find.text('Choose album'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('First — Artist'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check storage'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(memory.tab.artwork, isNull);
  });
  test(
    'concurrent and repeated searches share one MusicBrainz request',
    () async {
      final gate = Completer<http.Response>();
      var requests = 0;
      final service = ArtworkService(
        cacheDirectory: dir,
        pacer: instantPacer(),
        client: MockClient((_) {
          requests++;
          return gate.future;
        }),
      );
      final first = service.candidates('Artist', 'Song');
      final second = service.automaticCandidate('Artist', 'Song');
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      gate.complete(
        http.Response(
          jsonEncode({
            'count': 1,
            'recordings': [recording()],
          }),
          200,
        ),
      );
      expect((await first).single.id, id1);
      expect((await second)!.id, id1);
      expect((await service.candidates('Artist', 'Song')).single.id, id1);
      expect(requests, 1);
    },
  );

  test('concurrent requests for the same cover download it once', () async {
    final gate = Completer<http.Response>();
    var listings = 0, downloads = 0;
    final service = ArtworkService(
      cacheDirectory: dir,
      pacer: instantPacer(),
      client: MockClient((request) async {
        if (request.url.host == 'coverartarchive.org') {
          listings++;
          return http.Response(jsonEncode(cover()), 200);
        }
        downloads++;
        return gate.future;
      }),
    );
    final album = const AlbumCandidate(id1, 'First', 'Artist', '2000');
    final first = service.select(album), second = service.select(album);
    while (downloads == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(listings, 1);
    expect(downloads, 1);
    gate.complete(
      http.Response.bytes(
        base64Decode(png),
        200,
        headers: {'content-type': 'image/png'},
      ),
    );
    expect(
      (jsonDecode(await first) as Map)['local_path'],
      (jsonDecode(await second) as Map)['local_path'],
    );
    expect(downloads, 1);
  });

  test('timeouts and rate-limited artwork leave tabs usable', () async {
    final timeout = ArtworkService(
      cacheDirectory: dir,
      pacer: instantPacer(),
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      timeout.candidates('Artist', 'Song'),
      throwsA(isA<TimeoutException>()),
    );
    final limited = serviceFor(
      (request) => request.url.host == 'musicbrainz.org'
          ? http.Response(
              jsonEncode({
                'count': 1,
                'recordings': [recording()],
              }),
              200,
            )
          : http.Response('', 503),
    );
    await limited.assignAutomatically(repo, tab);
    expect((await repo.getById(tab.id!))!.artwork, isNull);
    expect((await repo.getById(tab.id!))!.asciiTab, tab.asciiTab);
  });
  test('reads MusicBrainz artist-credit fallback and release artist', () async {
    final payload = {
      'count': 1,
      'recordings': [
        {
          'title': 'Song',
          'score': '100',
          'artist-credit': [
            {
              'artist': {'name': 'Artist'},
            },
          ],
          'releases': [
            {
              'id': id1,
              'title': 'Compilation',
              'date': '2000',
              'artist-credit': [
                {
                  'artist': {'name': 'Various Artists'},
                },
              ],
            },
          ],
        },
      ],
    };
    final service = serviceFor((_) => http.Response(jsonEncode(payload), 200));
    final albums = await service.candidates('Artist', 'Song');
    expect(albums.single.artist, 'Various Artists');
    expect((await service.automaticCandidate('Artist', 'Song'))!.id, id1);
  });
  test('uses 250px thumbnail when 500px image is unavailable', () async {
    final seen = <Uri>[];
    final service = serviceFor((request) {
      seen.add(request.url);
      if (request.url.host == 'coverartarchive.org') {
        return http.Response(jsonEncode(cover()), 200);
      }
      if (request.url.path == '/cover.png') return http.Response('', 404);
      return http.Response.bytes(
        base64Decode(png),
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    final result = jsonDecode(
      await service.select(
        const AlbumCandidate(id1, 'First', 'Artist', '2000'),
      ),
    ) as Map;
    expect(result['source_url'], 'https://archive.org/small.png');
    expect(result['local_path'], isNotNull);
    expect(seen.last.path, '/small.png');
  });

  test('placeholder metadata never triggers automatic lookup', () async {
    expect(ArtworkService.validMetadata('%ARTIST%'), isFalse);
    expect(ArtworkService.validMetadata('Unknown Artist'), isFalse);
    var requests = 0;
    final service = serviceFor((_) {
      requests++;
      throw StateError('unexpected request');
    });
    final unknown = tab.withMetadata(
      title: tab.title,
      artist: '%ARTIST%',
      instrument: tab.instrument,
      tuning: tab.tuning,
      capo: 0,
      bpm: null,
      tags: [],
      trackName: null,
    );
    await service.assignAutomatically(repo, unknown);
    expect(requests, 0);
  });

  testWidgets('library refreshes when automatic artwork is saved', (
    tester,
  ) async {
    final service = serviceFor((request) {
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(
          jsonEncode({
            'count': 1,
            'recordings': [recording()],
          }),
          200,
        );
      }
      if (request.url.host == 'coverartarchive.org') {
        return http.Response(jsonEncode(cover()), 200);
      }
      return http.Response.bytes(
        base64Decode(png),
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryScreen(repository: repo)),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AlbumArt>(find.byType(AlbumArt)).tab.artwork, isNull);
    await tester.runAsync(() => service.assignAutomatically(repo, tab));
    final stored = await tester.runAsync(() => repo.getById(tab.id!));
    expect(stored!.artwork, isNotNull, reason: 'database update');
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
        if (tester.widget<AlbumArt>(find.byType(AlbumArt)).tab.artwork !=
            null) {
          return;
        }
      }
    });
    expect(
      tester.widget<AlbumArt>(find.byType(AlbumArt)).tab.artwork,
      isNotNull,
    );
  });

  testWidgets('opening an existing song assigns artwork and respects removal', (
    tester,
  ) async {
    final memory = AutoMemoryRepo(tab);
    var requests = 0;
    final service = serviceFor((request) {
      requests++;
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(
          jsonEncode({
            'count': 1,
            'recordings': [recording()],
          }),
          200,
        );
      }
      if (request.url.host == 'coverartarchive.org') {
        return http.Response(jsonEncode(cover()), 200);
      }
      return http.Response.bytes(
        base64Decode(png),
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TabDetailScreen(
          tab: tab,
          repository: memory,
          artworkService: service,
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        if (memory.tab.artwork != null) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(memory.tab.artwork, isNotNull);
    expect(find.text('Change album'), findsOneWidget);
    await tester.tap(find.text('Remove album'));
    await tester.pumpAndSettle();
    final removed = memory.tab;
    expect(removed.artwork, ArtworkService.removedArtwork);
    final before = requests;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: TabDetailScreen(
          tab: removed,
          repository: memory,
          artworkService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(memory.tab.artwork, ArtworkService.removedArtwork);
    expect(requests, before);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('cached artwork renders offline on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final online = serviceFor(
        (request) => request.url.host == 'coverartarchive.org'
            ? http.Response(jsonEncode(cover()), 200)
            : http.Response.bytes(
                base64Decode(png),
                200,
                headers: {'content-type': 'image/png'},
              ),
      );
      final album = const AlbumCandidate(id1, 'First', 'Artist', '2000');
      final metadata = (await tester.runAsync(() => online.select(album)))!;
      var requests = 0;
      final offline = serviceFor((_) {
        requests++;
        throw http.ClientException('offline');
      });
      final restored = (await tester.runAsync(() => offline.select(album)))!;
      expect(requests, 0);
      expect(
        (jsonDecode(restored) as Map)['local_path'],
        (jsonDecode(metadata) as Map)['local_path'],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AlbumArt(tab: tab.copyWith(artwork: restored), size: 48),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.album_outlined), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  test(
    'truncated image data is rejected even when its signature is valid',
    () async {
      final service = serviceFor(
        (request) => request.url.host == 'coverartarchive.org'
            ? http.Response(jsonEncode(cover()), 200)
            : http.Response.bytes(
                base64Decode(png).sublist(0, 16),
                200,
                headers: {'content-type': 'image/png'},
              ),
      );
      await expectLater(
        service.select(const AlbumCandidate(id1, 'A', 'B', null)),
        throwsFormatException,
      );
    },
  );
}
