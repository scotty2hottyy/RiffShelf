import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AlbumCandidate {
  const AlbumCandidate(this.id, this.title, this.artist, this.date);
  final String id, title, artist;
  final String? date;
}

class ArtworkService {
  ArtworkService({String? baseUrl, http.Client? client, this.cacheDirectory})
    : baseUrl =
          baseUrl ?? const String.fromEnvironment('RIFFSHELF_API_BASE_URL'),
      client = client ?? http.Client();
  final String baseUrl;
  final http.Client client;
  final Directory? cacheDirectory;
  static final _id = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Uri endpoint(String path, [Map<String, String>? query]) {
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        !['http', 'https'].contains(base.scheme) ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/')) {
      throw const FormatException(
        'Configure a reachable backend to look up albums.',
      );
    }
    return base.replace(path: path, queryParameters: query);
  }

  Future<dynamic> _json(Uri uri) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException(
        'Album lookup unavailable. Please try again.',
      );
    }
    return jsonDecode(
      await response.stream.bytesToString().timeout(
        const Duration(seconds: 12),
      ),
    );
  }

  Future<List<AlbumCandidate>> candidates(String artist, String title) async {
    final data = await _json(
      endpoint('/api/v1/metadata/recordings', {
        'artist': artist,
        'title': title,
      }),
    );
    final result = <AlbumCandidate>[];
    final seen = <String>{};
    for (final recording in data['recordings'] as List) {
      for (final release in recording['releases'] as List) {
        final id = release['release_id'] as String;
        if (_id.hasMatch(id) && seen.add(id)) {
          result.add(
            AlbumCandidate(
              id,
              release['title'] as String,
              recording['artist'] as String,
              release['date'] as String?,
            ),
          );
        }
      }
    }
    return result;
  }

  static bool trusted(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      (uri.host == 'coverartarchive.org' ||
          uri.host == 'archive.org' ||
          uri.host.endsWith('.archive.org'));

  Future<String> select(AlbumCandidate album) async {
    if (!_id.hasMatch(album.id)) {
      throw const FormatException('Invalid release ID');
    }
    final data = await _json(
      endpoint('/api/v1/metadata/releases/${album.id}/artwork'),
    );
    final art = data['artwork'];
    String? local;
    String? sourceUrl;
    if (art != null) {
      sourceUrl = (art['thumbnail_500'] ?? art['thumbnail_250']) as String?;
      if (sourceUrl != null) {
        final dir =
            cacheDirectory ??
            Directory(p.join(await getDatabasesPath(), 'artwork'));
        await dir.create(recursive: true);
        final file = File(p.join(dir.path, '${album.id.toLowerCase()}.img'));
        if (!await file.exists() || await file.length() == 0) {
          var uri = Uri.parse(sourceUrl);
          http.StreamedResponse? response;
          for (var i = 0; i < 4; i++) {
            if (!trusted(uri)) {
              throw const FormatException('Untrusted artwork URL');
            }
            final request = http.Request('GET', uri)..followRedirects = false;
            response = await client
                .send(request)
                .timeout(const Duration(seconds: 12));
            if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
            final location = response.headers['location'];
            if (location == null) {
              throw const FormatException('Invalid artwork redirect');
            }
            uri = uri.resolve(location);
          }
          if (response == null ||
              response.statusCode != 200 ||
              !(response.headers['content-type'] ?? '')
                  .toLowerCase()
                  .startsWith('image/') ||
              (response.contentLength ?? 0) > 2000000) {
            throw const FormatException('Artwork unavailable');
          }
          final bytes = BytesBuilder();
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 12),
          )) {
            bytes.add(chunk);
            if (bytes.length > 2000000) {
              throw const FormatException('Artwork too large');
            }
          }
          if (bytes.isEmpty) throw const FormatException('Empty artwork');
          await file.writeAsBytes(bytes.takeBytes(), flush: true);
        }
        local = file.path;
      }
    }
    return jsonEncode({
      'release_id': album.id,
      'title': album.title,
      'artist': album.artist,
      'date': album.date,
      'local_path': local,
      'source_url': sourceUrl,
      'source': art?['source'],
      'attribution': art?['attribution'],
      'rights': art?['rights'],
    });
  }
}
