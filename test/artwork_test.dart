import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const id1 = 'a1ed26f7-3f11-4633-a3c7-4a4abfa3271f';
const id2 = 'cb3d57ed-69d6-4f7d-b1bd-1b4975ba6b90';
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';

class MemoryRepo implements TabRepository {
  MemoryRepo(this.tab);
  SavedTab tab;
  @override
  Future<SavedTab> save(SavedTab value) async {
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

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteTabRepository repo;
  late SavedTab tab;
  late ArtworkService service;
  var downloads = 0;
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
    downloads = 0;
    service = ArtworkService(
      baseUrl: 'http://localhost:8000',
      cacheDirectory: dir,
      client: MockClient((request) async {
        if (request.url.path.endsWith('recordings')) {
          return http.Response(
            jsonEncode({
              'recordings': [
                {
                  'artist': 'Artist',
                  'releases': [
                    {'release_id': id1, 'title': 'First', 'date': '2000'},
                    {'release_id': id2, 'title': 'Second', 'date': '2001'},
                  ],
                },
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'localhost') {
          return http.Response(
            jsonEncode({
              'artwork': {
                'thumbnail_500': 'https://archive.org/cover.png',
                'source': 'Cover Art Archive',
                'rights': null,
                'attribution': null,
              },
            }),
            200,
          );
        }
        downloads++;
        return http.Response.bytes(
          base64Decode(png),
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });

  testWidgets('requires a choice, supports correction and removal', (
    tester,
  ) async {
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
    expect(find.textContaining('First — Artist'), findsOneWidget);
    expect(find.textContaining('Second — Artist'), findsOneWidget);
    expect(memory.tab.artwork, isNull);
    await tester.tap(find.textContaining('Second — Artist'));
    await tester.pumpAndSettle();
    expect(artworkMetadata(memory.tab)!['release_id'], id2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change album'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('First — Artist'));
    await tester.pumpAndSettle();
    expect(artworkMetadata(memory.tab)!['release_id'], id1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove album'));
    await tester.pumpAndSettle();
    expect(memory.tab.artwork, isNull);
  });

  testWidgets('cached artwork renders offline and missing files fall back', (
    tester,
  ) async {
    final album = AlbumCandidate(id1, 'First', 'Artist', '2000');
    final data = (await tester.runAsync(() => service.select(album)))!;
    await tester.runAsync(() => service.select(album));
    expect(downloads, 1);
    final saved = tab.copyWith(artwork: data);
    await tester.pumpWidget(MaterialApp(home: AlbumArt(tab: saved, size: 48)));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.runAsync(
      () => File(artworkMetadata(saved)!['local_path'] as String).delete(),
    );
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.pumpWidget(
      MaterialApp(
        home: AlbumArt(
          key: const ValueKey('missing'),
          tab: tab.copyWith(
            artwork: jsonEncode({'local_path': '${dir.path}/missing.img'}),
          ),
          size: 48,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.album_outlined), findsOneWidget);
  });

  test('rejects untrusted redirects', () async {
    final bad = ArtworkService(
      baseUrl: 'http://localhost',
      cacheDirectory: dir,
      client: MockClient((request) async {
        if (request.url.host == 'localhost') {
          return http.Response(
            jsonEncode({
              'artwork': {'thumbnail_500': 'https://archive.org/a'},
            }),
            200,
          );
        }
        return http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example/image'},
        );
      }),
    );
    await expectLater(
      bad.select(const AlbumCandidate(id1, 'A', 'B', null)),
      throwsFormatException,
    );
  });
}
