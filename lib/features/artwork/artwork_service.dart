import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/database/tab_repository.dart';
import '../../core/models/saved_tab.dart';

class AlbumCandidate {
  const AlbumCandidate(this.id, this.title, this.artist, this.date);
  final String id, title, artist;
  final String? date;
}

/// Serializes requests across app instances and spaces their starts by one second.
class MusicBrainzPacer {
  MusicBrainzPacer({
    Duration Function()? clock,
    Future<void> Function(Duration)? wait,
  }) : _clock = clock ?? _stopwatchTime,
       _wait = wait ?? Future<void>.delayed;
  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _stopwatchTime() => _stopwatch.elapsed;
  final Duration Function() _clock;
  final Future<void> Function(Duration) _wait;
  Future<void> _tail = Future<void>.value();
  Duration _next = Duration.zero;

  Future<T> run<T>(Future<T> Function() operation) {
    final task = _tail.then((_) async {
      final remaining = _next - _clock();
      if (remaining > Duration.zero) await _wait(remaining);
      _next = _clock() + const Duration(seconds: 1);
      return operation();
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  void backOff(Duration duration) {
    final next = _clock() + duration;
    if (next > _next) _next = next;
  }
}

class ArtworkLookupException implements Exception {
  const ArtworkLookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _RecordingLookup {
  const _RecordingLookup(this.candidates, this.automatic);
  final List<AlbumCandidate> candidates;
  final AlbumCandidate? automatic;
}

class ArtworkService {
  ArtworkService({
    http.Client? client,
    this.cacheDirectory,
    MusicBrainzPacer? pacer,
    this.timeout = const Duration(seconds: 12),
  }) : client = client ?? http.Client(),
       _ownsClient = client == null,
       pacer = pacer ?? _sharedPacer;

  static const userAgent =
      'RiffShelf/1.0.0 (https://github.com/scotty2hottyy/RiffShelf)';
  static final _sharedPacer = MusicBrainzPacer();
  static final ArtworkService shared = ArtworkService();
  static final Stopwatch _cacheClock = Stopwatch()..start();
  static final _id = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _versions = <int, int>{};
  static final _locks = <int, Future<void>>{};
  static final _downloads = <String, Future<String>>{};
  final http.Client client;
  final bool _ownsClient;
  final Directory? cacheDirectory;
  final MusicBrainzPacer pacer;
  final Duration timeout;
  final _lookupCache = <String, (Duration, _RecordingLookup)>{};
  final _pendingLookups = <String, Future<_RecordingLookup>>{};

  void dispose() {
    if (_ownsClient) client.close();
  }

  static void scheduleAutomatic(
    TabRepository repository,
    SavedTab tab, {
    ArtworkService? service,
  }) {
    if (repository is! AutomaticArtworkRepository ||
        tab.id == null ||
        !validMetadata(tab.artist) ||
        !validMetadata(tab.title)) {
      return;
    }
    final lookup = service ?? shared;
    unawaited(lookup.assignAutomatically(repository, tab));
  }

  static void cancelAutomatic(int id) =>
      _versions[id] = (_versions[id] ?? 0) + 1;

  /// Serialize automatic and explicit artwork writes for a tab.
  static Future<T> withTabLock<T>(int id, Future<T> Function() action) {
    final previous = _locks[id] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final done = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _locks[id] = done;
    done.whenComplete(() {
      if (identical(_locks[id], done)) _locks.remove(id);
    });
    return result;
  }

  static bool validMetadata(String value) {
    final text = value.trim();
    return text.isNotEmpty &&
        text.length <= 120 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(text) &&
        !RegExp(r'^(%[^%]+%|<[^>]+>|\[[^\]]+\])$').hasMatch(text) &&
        !const {
          'unknown',
          'unknown artist',
          'unknown title',
        }.contains(text.toLowerCase());
  }

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  static String _escape(String value) => value.replaceAllMapped(
    RegExp(r'([+\-!(){}\[\]^"~*?:\\/])'),
    (m) => '\\${m[0]}',
  );

  static String _artistCredit(Object? value) {
    if (value is! List || value.isEmpty) {
      throw const FormatException('Missing artist credit');
    }
    final buffer = StringBuffer();
    for (final part in value) {
      if (part is String) {
        buffer.write(part);
      } else if (part is Map) {
        final artist = part['artist'];
        final name = part['name'] ?? (artist is Map ? artist['name'] : null);
        if (name is! String || name.trim().isEmpty) {
          throw const FormatException('Invalid artist credit');
        }
        buffer.write(name);
        if (part['joinphrase'] is String) buffer.write(part['joinphrase']);
      } else {
        throw const FormatException('Invalid artist credit');
      }
    }
    final result = buffer.toString().trim();
    if (result.isEmpty) throw const FormatException('Missing artist');
    return result;
  }

  Future<http.StreamedResponse> _send(
    Uri uri, {
    String accept = 'application/json',
  }) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers.addAll({'User-Agent': userAgent, 'Accept': accept});
    return client.send(request).timeout(timeout);
  }

  Future<Uint8List> _bytes(http.StreamedResponse response, int limit) async {
    if ((response.contentLength ?? 0) > limit) {
      await response.stream.listen((_) {}).cancel();
      throw const FormatException('Response too large');
    }
    final builder = BytesBuilder();
    await for (final chunk in response.stream.timeout(timeout)) {
      builder.add(chunk);
      if (builder.length > limit) {
        throw const FormatException('Response too large');
      }
    }
    return builder.takeBytes();
  }

  Future<_RecordingLookup> _lookup(String artist, String title) async {
    if (!validMetadata(artist) || !validMetadata(title)) {
      throw const ArtworkLookupException(
        'Add a song title and artist before looking up albums.',
      );
    }
    final key = jsonEncode([_normalize(artist), _normalize(title)]);
    final cached = _lookupCache[key];
    if (cached != null && cached.$1 > _cacheClock.elapsed) return cached.$2;
    final existing = _pendingLookups[key];
    if (existing != null) return existing;
    final pending = _requestLookup(artist, title);
    _pendingLookups[key] = pending;
    try {
      final result = await pending;
      if (_lookupCache.length >= 100) {
        _lookupCache.remove(_lookupCache.keys.first);
      }
      _lookupCache[key] = (
        _cacheClock.elapsed + const Duration(minutes: 5),
        result,
      );
      return result;
    } finally {
      if (identical(_pendingLookups[key], pending)) _pendingLookups.remove(key);
    }
  }

  Future<_RecordingLookup> _requestLookup(String artist, String title) async {
    final uri = Uri.https('musicbrainz.org', '/ws/2/recording/', {
      'query':
          'artistname:"${_escape(artist.trim())}" AND recording:"${_escape(title.trim())}"',
      'fmt': 'json',
      'limit': '100',
    });
    return pacer.run(() async {
      final response = await _send(uri);
      if (response.statusCode == 429 || response.statusCode == 503) {
        await response.stream.listen((_) {}).cancel();
        final seconds =
            (int.tryParse(response.headers['retry-after'] ?? '') ?? 5).clamp(
              1,
              60,
            );
        pacer.backOff(Duration(seconds: seconds));
        throw const ArtworkLookupException(
          'MusicBrainz is busy. Please try again shortly.',
        );
      }
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw const ArtworkLookupException(
          'MusicBrainz lookup is unavailable.',
        );
      }
      final payload = jsonDecode(utf8.decode(await _bytes(response, 2000000)));
      if (payload is! Map || payload['recordings'] is! List) {
        throw const FormatException('Invalid MusicBrainz response');
      }
      final recordings = payload['recordings'] as List;
      final count = payload['count'];
      var complete =
          count is int &&
          count == recordings.length &&
          (payload['offset'] == null || payload['offset'] == 0);
      var confident = false;
      final candidates = <String, AlbumCandidate>{};
      final exactReleases = <String, AlbumCandidate>{};
      for (final raw in recordings) {
        if (raw is! Map ||
            raw['title'] is! String ||
            raw['artist-credit'] is! List) {
          throw const FormatException('Invalid recording');
        }
        final credited = _artistCredit(raw['artist-credit']);
        final exact =
            _normalize(raw['title'] as String) == _normalize(title) &&
            _normalize(credited) == _normalize(artist);
        final score = int.tryParse('${raw['score'] ?? ''}');
        if (exact && score != null && score >= 95 && score <= 100) {
          confident = true;
        }
        final releases = raw['releases'] ?? const [];
        if (releases is! List) throw const FormatException('Invalid releases');
        if (exact && releases.isEmpty) complete = false;
        for (final release in releases) {
          if (release is! Map ||
              release['id'] is! String ||
              !_id.hasMatch(release['id'] as String) ||
              release['title'] is! String ||
              (release['title'] as String).trim().isEmpty) {
            complete = false;
            continue;
          }
          final rawDate = release['date'];
          if (rawDate != null && rawDate is! String) {
            complete = false;
            continue;
          }
          final date = rawDate is String && rawDate.trim().isEmpty
              ? null
              : rawDate as String?;
          if (date != null &&
              !RegExp(r'^\d{4}(?:-\d{2})?(?:-\d{2})?$').hasMatch(date)) {
            complete = false;
            continue;
          }
          String releaseArtist;
          try {
            releaseArtist = release['artist-credit'] == null
                ? credited
                : _artistCredit(release['artist-credit']);
          } on FormatException {
            complete = false;
            continue;
          }
          final id = (release['id'] as String).toLowerCase();
          final candidate = AlbumCandidate(
            id,
            (release['title'] as String).trim(),
            releaseArtist,
            date,
          );
          candidates.putIfAbsent(id, () => candidate);
          if (exact) {
            exactReleases.putIfAbsent(id, () => candidate);
            candidates[id] = exactReleases[id]!;
          }
        }
      }
      final auto = complete && confident && exactReleases.length == 1
          ? exactReleases.values.single
          : null;
      return _RecordingLookup(candidates.values.toList(growable: false), auto);
    });
  }

  Future<List<AlbumCandidate>> candidates(String artist, String title) async =>
      (await _lookup(artist, title)).candidates;
  Future<AlbumCandidate?> automaticCandidate(
    String artist,
    String title,
  ) async => (await _lookup(artist, title)).automatic;

  /// Automatic work never delays saving, never replaces a selection, and never throws.
  Future<void> assignAutomatically(
    TabRepository repository,
    SavedTab tab,
  ) async {
    if (repository is! AutomaticArtworkRepository ||
        tab.id == null ||
        tab.artwork != null ||
        tab.albumArt != null ||
        !validMetadata(tab.artist) ||
        !validMetadata(tab.title)) {
      return;
    }
    final id = tab.id!;
    final version = _versions[id] ?? 0;
    try {
      final album = await automaticCandidate(tab.artist, tab.title);
      if (album == null || (_versions[id] ?? 0) != version) return;
      final metadata = await select(album);
      final parsed = jsonDecode(metadata);
      if (parsed is! Map || parsed['local_path'] is! String) return;
      await withTabLock(id, () async {
        if ((_versions[id] ?? 0) != version) return;
        await (repository as AutomaticArtworkRepository).setArtworkIfUnselected(
          id: id,
          artist: tab.artist,
          title: tab.title,
          artwork: metadata,
        );
      });
    } catch (_) {
      // Lookup, connectivity, and cache failures never block saved tabs.
    }
  }

  /// CAA may publish HTTP archive links; only approved hosts are upgraded before use.
  static Uri _archiveUri(String value, [Uri? base]) {
    final parsed = Uri.tryParse(value);
    if (parsed == null) throw const FormatException('Invalid artwork URL');
    final uri = base == null ? parsed : base.resolveUri(parsed);
    final host = uri.host.toLowerCase();
    if (!uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment ||
        !(host == 'coverartarchive.org' ||
            host == 'archive.org' ||
            host.endsWith('.archive.org'))) {
      throw const FormatException('Untrusted artwork URL');
    }
    return uri.replace(scheme: 'https');
  }

  static bool trusted(Uri uri) {
    try {
      return uri.scheme == 'https' && _archiveUri(uri.toString()) == uri;
    } catch (_) {
      return false;
    }
  }

  Future<http.StreamedResponse> _archiveGet(
    Uri initial, {
    String accept = 'application/json',
  }) async {
    var uri = _archiveUri(initial.toString());
    for (var i = 0; i < 4; i++) {
      final response = await _send(uri, accept: accept);
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      await response.stream.listen((_) {}).cancel();
      if (location == null) {
        throw const FormatException('Invalid artwork redirect');
      }
      uri = _archiveUri(location, uri);
    }
    throw const FormatException('Too many artwork redirects');
  }

  static bool _validImage(Uint8List bytes) =>
      (bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0d &&
          bytes[5] == 0x0a &&
          bytes[6] == 0x1a &&
          bytes[7] == 0x0a) ||
      (bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff) ||
      (bytes.length >= 12 &&
          ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
          ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') ||
      (bytes.length >= 6 &&
          [
            'GIF87a',
            'GIF89a',
          ].contains(ascii.decode(bytes.sublist(0, 6), allowInvalid: true)));

  static bool _matchesImageType(Uint8List bytes, String type) {
    switch (type) {
      case 'image/png':
        return bytes.length >= 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4e &&
            bytes[3] == 0x47;
      case 'image/jpeg':
        return bytes.length >= 3 &&
            bytes[0] == 0xff &&
            bytes[1] == 0xd8 &&
            bytes[2] == 0xff;
      case 'image/webp':
        return bytes.length >= 12 &&
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
      case 'image/gif':
        return bytes.length >= 6 &&
            [
              'GIF87a',
              'GIF89a',
            ].contains(ascii.decode(bytes.sublist(0, 6), allowInvalid: true));
      default:
        return false;
    }
  }

  // Bound decoded dimensions as well as transfer size, and reject truncated files.
  static Future<bool> _decodable(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width > 2048 ||
          descriptor.height > 2048 ||
          descriptor.width * descriptor.height > 4000000) {
        return false;
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width > 500 ? 500 : null,
      );
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      return true;
    } catch (_) {
      return false;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<String> select(AlbumCandidate album) async {
    if (!_id.hasMatch(album.id)) {
      throw const FormatException('Invalid release ID');
    }
    final id = album.id.toLowerCase();
    final dir =
        cacheDirectory ??
        Directory(p.join(await getDatabasesPath(), 'artwork'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '$id.img'));
    String? local;
    String? sourceUrl;
    var cached = false;
    if (await file.exists() &&
        await file.length() > 0 &&
        await file.length() <= 2000000) {
      final bytes = await file.readAsBytes();
      cached = _validImage(bytes) && await _decodable(bytes);
    }
    if (cached) {
      local = file.path;
      sourceUrl = 'https://coverartarchive.org/release/$id/front';
    } else {
      final key = file.path;
      final job = _downloads.putIfAbsent(key, () => _fetchCover(id, file));
      try {
        final source = await job;
        if (source.isNotEmpty) {
          local = file.path;
          sourceUrl = source;
        }
      } finally {
        if (identical(_downloads[key], job)) _downloads.remove(key);
      }
    }
    return jsonEncode({
      'release_id': id,
      'title': album.title,
      'artist': album.artist,
      'date': album.date,
      'local_path': local,
      'source_url': sourceUrl,
      'source': 'Cover Art Archive',
      'attribution': null,
      'rights': null,
    });
  }

  Future<String> _fetchCover(String id, File file) async {
    final response = await _archiveGet(
      Uri.https('coverartarchive.org', '/release/$id'),
    );
    if (response.statusCode == 404) {
      await response.stream.listen((_) {}).cancel();
      return '';
    }
    if (response.statusCode == 429 || response.statusCode == 503) {
      await response.stream.listen((_) {}).cancel();
      throw const ArtworkLookupException(
        'Cover Art Archive is busy. Please try again shortly.',
      );
    }
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw const ArtworkLookupException('Cover artwork is unavailable.');
    }
    final payload = jsonDecode(utf8.decode(await _bytes(response, 2000000)));
    if (payload is! Map || payload['images'] is! List) {
      throw const FormatException('Invalid artwork response');
    }
    for (final image in payload['images'] as List) {
      if (image is! Map || image['front'] is! bool) {
        throw const FormatException('Invalid artwork image');
      }
      if (image['front'] != true || image['approved'] == false) continue;
      final thumbs = image['thumbnails'];
      if (thumbs is! Map) {
        throw const FormatException('Invalid artwork thumbnails');
      }
      for (final url in [thumbs['500'], thumbs['250']]) {
        if (url == null) continue;
        if (url is! String) throw const FormatException('Invalid artwork URL');
        final source = _archiveUri(url);
        final imageResponse = await _archiveGet(
          source,
          accept: 'image/jpeg, image/png, image/webp, image/gif',
        );
        if (imageResponse.statusCode == 404) {
          await imageResponse.stream.listen((_) {}).cancel();
          continue;
        }
        if (imageResponse.statusCode == 429 ||
            imageResponse.statusCode == 503) {
          await imageResponse.stream.listen((_) {}).cancel();
          throw const ArtworkLookupException(
            'Cover Art Archive is busy. Please try again shortly.',
          );
        }
        final type = (imageResponse.headers['content-type'] ?? '')
            .split(';')
            .first
            .trim()
            .toLowerCase();
        if (imageResponse.statusCode != 200 ||
            !const {
              'image/jpeg',
              'image/png',
              'image/webp',
              'image/gif',
            }.contains(type)) {
          await imageResponse.stream.listen((_) {}).cancel();
          throw const FormatException('Invalid artwork type');
        }
        final bytes = await _bytes(imageResponse, 2000000);
        if (!_validImage(bytes) ||
            !_matchesImageType(bytes, type) ||
            !await _decodable(bytes)) {
          throw const FormatException('Invalid image data');
        }
        final tmp = File(
          '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        try {
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(file.path);
        } finally {
          if (await tmp.exists()) await tmp.delete();
        }
        return source.toString();
      }
      return '';
    }
    return '';
  }
}
