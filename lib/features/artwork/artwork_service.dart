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

/// A MusicBrainz release the user can choose as a tab's album.
///
/// [alternateEditions] groups other releases of the same album (such as
/// remasters) so the picker can show one entry per album.
class AlbumCandidate {
  const AlbumCandidate(
    this.id,
    this.title,
    this.artist,
    this.date, {
    this.releaseGroupId,
    this.primaryType,
    this.secondaryTypes = const <String>{},
    this.isStudioAlbum = true,
    this.alternateEditions = const <AlbumCandidate>[],
  });
  final String id, title, artist;
  final String? date;
  final String? releaseGroupId;
  final String? primaryType;
  final Set<String> secondaryTypes;
  final bool isStudioAlbum;
  final List<AlbumCandidate> alternateEditions;

  AlbumCandidate copyWith({
    String? id,
    String? title,
    String? artist,
    String? date,
    String? releaseGroupId,
    String? primaryType,
    Set<String>? secondaryTypes,
    bool? isStudioAlbum,
    List<AlbumCandidate>? alternateEditions,
  }) => AlbumCandidate(
    id ?? this.id,
    title ?? this.title,
    artist ?? this.artist,
    date ?? this.date,
    releaseGroupId: releaseGroupId ?? this.releaseGroupId,
    primaryType: primaryType ?? this.primaryType,
    secondaryTypes: secondaryTypes ?? this.secondaryTypes,
    isStudioAlbum: isStudioAlbum ?? this.isStudioAlbum,
    alternateEditions: alternateEditions ?? this.alternateEditions,
  );
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

/// Raised when an artwork search or download fails. [message] is safe to
/// show to the user.
class ArtworkLookupException implements Exception {
  const ArtworkLookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _RankedAlbum {
  const _RankedAlbum(
    this.album,
    this.score,
    this.groupDate,
    this.groupId,
    this.automatic,
  );
  final AlbumCandidate album;
  final int score;
  final String? groupDate;
  final String? groupId;
  final bool automatic;
}

class _RecordingLookup {
  const _RecordingLookup(this.ranked);
  final List<_RankedAlbum> ranked;
  List<AlbumCandidate> get candidates => [
    for (final item in ranked) item.album,
  ];
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
  static final _automaticJobs = <(TabRepository, int, int), Future<void>>{};
  static const removedArtwork = '{"removed":true}';
  static const _automaticLimit = 8;
  final http.Client client;
  final bool _ownsClient;
  final Directory? cacheDirectory;
  final MusicBrainzPacer pacer;
  final Duration timeout;
  final _lookupCache = <String, (Duration, _RecordingLookup)>{};
  final _pendingLookups = <String, Future<_RecordingLookup>>{};
  final _missingCovers = <String, Duration>{};

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
      final candidates = <String, _RankedAlbum>{};
      for (final raw in recordings) {
        if (raw is! Map || raw['title'] is! String) continue;
        String credited;
        try {
          credited = _artistCredit(raw['artist-credit']);
        } on FormatException {
          continue;
        }
        final artistExact = _normalize(credited) == _normalize(artist);
        final titleExact =
            _normalize(raw['title'] as String) == _normalize(title);
        final matchScore = int.tryParse('${raw['score'] ?? ''}') ?? 0;
        final eligible = artistExact && (titleExact || matchScore >= 95);
        final releases = raw['releases'];
        if (releases is! List) continue;
        for (final release in releases) {
          if (release is! Map ||
              release['id'] is! String ||
              !_id.hasMatch(release['id'] as String) ||
              release['title'] is! String ||
              (release['title'] as String).trim().isEmpty) {
            continue;
          }
          final rawDate = release['date'];
          if (rawDate != null && rawDate is! String) continue;
          final date = rawDate is String && rawDate.trim().isEmpty
              ? null
              : rawDate as String?;
          if (date != null &&
              !RegExp(r'^\d{4}(?:-\d{2})?(?:-\d{2})?$').hasMatch(date)) {
            continue;
          }
          String releaseArtist;
          try {
            releaseArtist = release['artist-credit'] == null
                ? credited
                : _artistCredit(release['artist-credit']);
          } on FormatException {
            continue;
          }
          final group = release['release-group'];
          final groupMap = group is Map ? group : const {};
          final rawPrimary = groupMap['primary-type'];
          final primary = rawPrimary is String
              ? rawPrimary.trim().toLowerCase()
              : '';
          final secondary = groupMap['secondary-types'] is List
              ? (groupMap['secondary-types'] as List)
                    .whereType<String>()
                    .map((value) => value.trim().toLowerCase())
                    .toSet()
              : <String>{};
          final releaseDisambiguation = release['disambiguation'];
          final rawDisambiguation = raw['disambiguation'];
          final descriptor =
              '${release['title']} ${releaseDisambiguation is String ? releaseDisambiguation : ''} ${rawDisambiguation is String ? rawDisambiguation : ''}'
                  .toLowerCase();
          final status = '${release['status'] ?? ''}'.trim().toLowerCase();
          final isLive =
              secondary.contains('live') ||
              RegExp(r'\blive\b').hasMatch(descriptor);
          final isCompilation =
              secondary.contains('compilation') ||
              RegExp(r'\b(greatest hits|best of|anthology|collection)\b')
                  .hasMatch(descriptor);
          var rank = (artistExact ? 10000 : 0) + (titleExact ? 5000 : 0);
          rank += primary == 'album'
              ? 1000
              : primary == 'single'
              ? 400
              : 0;
          if (isCompilation) rank -= 700;
          if (isLive) rank -= 800;
          if (secondary.contains('remix')) rank -= 300;
          if (status == 'bootleg') {
            rank -= 200;
          }
          final firstDate = groupMap['first-release-date'];
          final groupDate =
              firstDate is String &&
                  RegExp(r'^\d{4}(?:-\d{2})?(?:-\d{2})?$').hasMatch(firstDate)
              ? firstDate
              : date;
          final id = (release['id'] as String).toLowerCase();
          final isStudio = isStudioRelease(
            primaryType: rawPrimary is String ? rawPrimary : null,
            secondaryTypes: secondary,
            status: status.isEmpty ? null : status,
            title: release['title'] as String,
            disambiguation:
                '${releaseDisambiguation is String ? releaseDisambiguation : ''} ${rawDisambiguation is String ? rawDisambiguation : ''}'
                    .trim(),
          );
          final candidate = _RankedAlbum(
            AlbumCandidate(
              id,
              (release['title'] as String).trim(),
              releaseArtist,
              date,
              releaseGroupId: groupMap['id'] is String
                  ? groupMap['id'] as String
                  : null,
              primaryType: rawPrimary is String ? rawPrimary : null,
              secondaryTypes: secondary,
              isStudioAlbum: isStudio,
            ),
            rank,
            groupDate,
            groupMap['id'] is String ? groupMap['id'] as String : null,
            eligible,
          );
          final previous = candidates[id];
          if (previous == null || _compareAlbums(candidate, previous) < 0) {
            candidates[id] = candidate;
          }
        }
      }
      final ranked = candidates.values.toList()..sort(_compareAlbums);
      return _RecordingLookup(ranked);
    });
  }

  static bool isStudioRelease({
    String? primaryType,
    Set<String> secondaryTypes = const {},
    String? status,
    String? title,
    String? disambiguation,
  }) {
    final primary = (primaryType ?? '').trim().toLowerCase();
    final secondaries = secondaryTypes
        .map((s) => s.trim().toLowerCase())
        .toSet();
    final stat = (status ?? '').trim().toLowerCase();
    final descriptor = '${title ?? ''} ${disambiguation ?? ''}'.toLowerCase();

    // 1. Release status: bootlegs are hidden
    if (stat == 'bootleg') return false;

    // 2. Primary type: hide singles, EPs, and other non-album primary types
    if (primary.isNotEmpty && primary != 'album') {
      return false;
    }

    // 3. Secondary types: hide live, compilation, remix, bootleg, etc.
    if (secondaries.contains('live') ||
        secondaries.contains('compilation') ||
        secondaries.contains('remix') ||
        secondaries.contains('dj-mix') ||
        secondaries.contains('bootleg') ||
        secondaries.contains('mixtape/street') ||
        secondaries.contains('demo')) {
      return false;
    }

    // 4. Descriptor / text indicators (matches live, compilations, greatest hits, bootlegs, singles, EPs, remixes)
    if (RegExp(r'\blive\b').hasMatch(descriptor)) return false;
    if (RegExp(r'\b(greatest hits|best of|anthology|collection|compilation)\b')
        .hasMatch(descriptor)) {
      return false;
    }
    if (RegExp(r'\bbootleg\b').hasMatch(descriptor)) return false;
    if (RegExp(r'\b(remix|remixes)\b').hasMatch(descriptor)) return false;
    if (RegExp(r'\bsingle\b').hasMatch(descriptor)) return false;
    if (RegExp(r'\bep\b').hasMatch(descriptor)) return false;

    return true;
  }

  static List<AlbumCandidate> filterStudioAlbums(
    List<AlbumCandidate> candidates,
  ) => candidates.where((c) => c.isStudioAlbum).toList();

  static List<AlbumCandidate> groupCandidates(List<AlbumCandidate> candidates) {
    final groupIndex = <String, int>{};
    final result = <AlbumCandidate>[];

    for (final candidate in candidates) {
      final groupId = candidate.releaseGroupId;
      if (groupId == null || groupId.isEmpty) {
        result.add(candidate);
        continue;
      }
      final index = groupIndex[groupId];
      if (index == null) {
        groupIndex[groupId] = result.length;
        result.add(candidate);
      } else {
        final existing = result[index];
        result[index] = existing.copyWith(
          alternateEditions: [...existing.alternateEditions, candidate],
        );
      }
    }
    return result;
  }

  static int _compareAlbums(_RankedAlbum a, _RankedAlbum b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byGroupDate = (a.groupDate ?? '9999').compareTo(
      b.groupDate ?? '9999',
    );
    if (byGroupDate != 0) return byGroupDate;
    final byDate = (a.album.date ?? '9999').compareTo(b.album.date ?? '9999');
    if (byDate != 0) return byDate;
    return a.album.id.compareTo(b.album.id);
  }

  Future<List<AlbumCandidate>> candidates(String artist, String title) async =>
      (await _lookup(artist, title)).candidates;
  Future<AlbumCandidate?> automaticCandidate(
    String artist,
    String title,
  ) async => (await automaticCandidates(artist, title)).firstOrNull;

  Future<List<AlbumCandidate>> automaticCandidates(
    String artist,
    String title,
  ) async {
    final ranked = (await _lookup(artist, title)).ranked;
    final groupAttempts = <String, int>{};
    final result = <AlbumCandidate>[];
    for (final item in ranked) {
      if (!item.automatic) continue;
      final group = item.groupId;
      if (group != null && (groupAttempts[group] ?? 0) >= 2) continue;
      if (result.length >= _automaticLimit) break;
      if (group != null) {
        groupAttempts[group] = (groupAttempts[group] ?? 0) + 1;
      }
      result.add(item.album);
    }
    return result;
  }

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
    final key = (repository, id, version);
    final existing = _automaticJobs[key];
    if (existing != null) return existing;
    final job = _assignRanked(repository, tab, version);
    _automaticJobs[key] = job;
    try {
      await job;
    } finally {
      if (identical(_automaticJobs[key], job)) _automaticJobs.remove(key);
    }
  }

  Future<void> _assignRanked(
    TabRepository repository,
    SavedTab tab,
    int version,
  ) async {
    final id = tab.id!;
    try {
      final albums = await automaticCandidates(tab.artist, tab.title);
      for (final album in albums) {
        if ((_versions[id] ?? 0) != version) return;
        final metadata = await _tryCover(album);
        if (metadata == null) continue;
        await withTabLock(id, () async {
          if ((_versions[id] ?? 0) != version) return;
          await (repository as AutomaticArtworkRepository)
              .setArtworkIfUnselected(
                id: id,
                artist: tab.artist,
                title: tab.title,
                artwork: metadata,
              );
        });
        return;
      }
    } catch (_) {
      // Connectivity, rate limits, and cache failures never block saved tabs.
    }
  }

  /// Finds the best ranked album with a usable Cover Art Archive image,
  /// trying candidates in order until one succeeds. Shared by automatic
  /// save/import artwork assignment and by search-result artwork previews,
  /// so a result already looked up during search is not re-fetched when the
  /// song is saved.
  Future<String?> bestMatchArtwork(String artist, String title) async {
    for (final album in await automaticCandidates(artist, title)) {
      final metadata = await _tryCover(album);
      if (metadata != null) return metadata;
    }
    return null;
  }

  Future<String?> _tryCover(AlbumCandidate album) async {
    if ((_missingCovers[album.id] ?? Duration.zero) > _cacheClock.elapsed) {
      return null;
    }
    String metadata;
    try {
      metadata = await select(album);
    } on FormatException {
      // A malformed cover should not prevent trying another release.
      return null;
    } on ArtworkLookupException catch (error) {
      if (error.message == 'Cover artwork is unavailable.') return null;
      rethrow;
    }
    final parsed = jsonDecode(metadata);
    if (parsed is! Map || parsed['local_path'] is! String) {
      if (_missingCovers.length >= 100) {
        _missingCovers.remove(_missingCovers.keys.first);
      }
      _missingCovers[album.id] =
          _cacheClock.elapsed + const Duration(minutes: 5);
      return null;
    }
    _missingCovers.remove(album.id);
    return metadata;
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

    String? local;
    String? sourceUrl;
    String successfulId = id;

    final primary = await _obtainCover(id, dir);
    if (primary.$1 != null) {
      local = primary.$1;
      sourceUrl = primary.$2;
      successfulId = id;
    } else if (album.alternateEditions.isNotEmpty) {
      for (final alt in album.alternateEditions) {
        if (!_id.hasMatch(alt.id)) continue;
        try {
          final altCover = await _obtainCover(alt.id.toLowerCase(), dir);
          if (altCover.$1 != null) {
            local = altCover.$1;
            sourceUrl = altCover.$2;
            successfulId = alt.id.toLowerCase();
            break;
          }
        } on ArtworkLookupException {
          rethrow;
        } catch (_) {
          continue;
        }
      }
    }

    return jsonEncode({
      'release_id': successfulId,
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

  Future<(String? local, String? sourceUrl)> _obtainCover(
    String id,
    Directory dir,
  ) async {
    final file = File(p.join(dir.path, '$id.img'));
    var cached = false;
    if (await file.exists() &&
        await file.length() > 0 &&
        await file.length() <= 2000000) {
      final bytes = await file.readAsBytes();
      cached = _validImage(bytes) && await _decodable(bytes);
    }
    if (cached) {
      return (file.path, 'https://coverartarchive.org/release/$id/front');
    }
    final key = file.path;
    final job = _downloads.putIfAbsent(key, () => _fetchCover(id, file));
    try {
      final source = await job;
      if (source.isNotEmpty) {
        return (file.path, source);
      }
      return (null, null);
    } finally {
      if (identical(_downloads[key], job)) _downloads.remove(key);
    }
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
