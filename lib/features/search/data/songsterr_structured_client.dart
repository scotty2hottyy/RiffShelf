import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/models/instrument_type.dart';
import '../../../core/models/saved_tab.dart';
import '../../../core/models/tab_structure.dart';
import '../domain/tab_source_provider.dart';
import 'songsterr_diagnostics.dart';

class SongsterrSongData {
  const SongsterrSongData({
    required this.songId,
    required this.revisionId,
    required this.image,
    required this.title,
    required this.artist,
    required this.tracks,
    this.bpm,
    this.source,
  });
  final String songId;
  final String revisionId;
  final String image;
  final String title;
  final String artist;
  final int? bpm;
  final String? source;
  final List<SongsterrTrackMetadata> tracks;
}

class SongsterrTrackMetadata {
  const SongsterrTrackMetadata({
    required this.partId,
    required this.name,
    required this.instrument,
    this.tuningMidi = const [],
    this.capo = 0,
    this.hash,
  });
  final int partId;
  final String name;
  final String instrument;
  final List<int> tuningMidi;
  final int capo;
  final String? hash;
  List<String> get tuning => tuningMidi.reversed.map(_midiToName).toList();
}

class SongsterrTrackData {
  const SongsterrTrackData({required this.metadata, required this.payload});
  final SongsterrTrackMetadata metadata;
  final Map<String, dynamic> payload;
}

class SongsterrStructuredClient {
  SongsterrStructuredClient({
    required this._client,
    this.timeout = const Duration(seconds: 8),
    this.baseUrl = 'https://www.songsterr.com',
    this.cdnHosts = const [
      'https://dqsljvtekg760.cloudfront.net',
      'https://d34shlm8p2ums2.cloudfront.net',
      'https://d3cqchs6g3b5ew.cloudfront.net',
    ],
    this.headers = const {'Accept': 'application/json'},
  });

  final http.Client _client;
  final Duration timeout;
  final String baseUrl;
  final List<String> cdnHosts;
  final Map<String, String> headers;
  String? _workingHost;

  /// Redirects are followed explicitly so downloads can never downgrade TLS.
  /// Status/body metadata is recorded; bodies and exception text never are.
  Future<http.Response> request(
    Uri uri,
    SongsterrStage stage,
    SongsterrDiagnostics trace,
  ) async {
    final clock = Stopwatch()..start();
    Duration remaining() {
      final left = timeout - clock.elapsed;
      return left.isNegative ? Duration.zero : left;
    }

    for (var redirects = 0; redirects <= 3; redirects++) {
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        trace.record(stage, failure: SongsterrFailure.httpError);
        throw SongsterrException(SongsterrFailure.httpError);
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll(headers);
      late final http.StreamedResponse streamed;
      try {
        streamed = await _client.send(request).timeout(remaining());
      } on TimeoutException {
        trace.record(
          stage,
          endpoint: uri,
          phase: SongsterrRequestPhase.response,
          failure: SongsterrFailure.timeout,
        );
        throw SongsterrException(SongsterrFailure.timeout);
      } on SocketException {
        trace.record(
          stage,
          endpoint: uri,
          phase: SongsterrRequestPhase.connection,
          failure: SongsterrFailure.networkUnreachable,
        );
        throw SongsterrException(SongsterrFailure.networkUnreachable);
      } on Object {
        trace.record(
          stage,
          endpoint: uri,
          phase: SongsterrRequestPhase.response,
          failure: SongsterrFailure.networkUnreachable,
        );
        throw SongsterrException(SongsterrFailure.networkUnreachable);
      }
      trace.record(
        stage,
        endpoint: uri,
        phase: SongsterrRequestPhase.response,
        status: streamed.statusCode,
      );
      late final http.Response response;
      try {
        response = await http.Response.fromStream(streamed)
            .timeout(remaining());
      } on TimeoutException {
        trace.record(
          stage,
          endpoint: uri,
          phase: SongsterrRequestPhase.bodyRead,
          status: streamed.statusCode,
          failure: SongsterrFailure.timeout,
        );
        throw SongsterrException(SongsterrFailure.timeout);
      } on Object {
        trace.record(
          stage,
          endpoint: uri,
          phase: SongsterrRequestPhase.bodyRead,
          status: streamed.statusCode,
          failure: SongsterrFailure.networkUnreachable,
        );
        throw SongsterrException(SongsterrFailure.networkUnreachable);
      }
      trace.record(
        stage,
        endpoint: uri,
        phase: SongsterrRequestPhase.bodyRead,
        status: response.statusCode,
        bytes: response.bodyBytes.length,
        contentType: response.headers['content-type'],
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode) &&
          response.headers['location'] != null) {
        uri = uri.resolve(response.headers['location']!);
        continue;
      }
      return response;
    }
    trace.record(stage, failure: SongsterrFailure.httpError);
    throw SongsterrException(SongsterrFailure.httpError);
  }

  Future<SongsterrSongData> fetchSong(
    String songId, {
    SongsterrDiagnostics? diagnostics,
  }) async {
    final trace = diagnostics ?? SongsterrDiagnostics(songId: songId);
    if (!RegExp(r'^\d+$').hasMatch(songId)) {
      trace.record(
        SongsterrStage.songMeta,
        failure: SongsterrFailure.metaParseError,
      );
      throw SongsterrException(SongsterrFailure.metaParseError);
    }
    final response = await request(
      Uri.parse('$baseUrl/api/meta/$songId'),
      SongsterrStage.songMeta,
      trace,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      trace.record(
        SongsterrStage.songMeta,
        failure: SongsterrFailure.httpError,
      );
      throw SongsterrException(
        SongsterrFailure.httpError,
        message: 'Song information could not be loaded.',
      );
    }
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) throw const FormatException();
      final revisionId = json['revisionId']?.toString();
      final image = json['image']?.toString();
      final rawTracks = json['tracks'];
      if (rawTracks is! List ||
          json['title'] is! String ||
          json['artist'] is! String) {
        throw const FormatException();
      }
      if (revisionId == null || !RegExp(r'^\d+$').hasMatch(revisionId)) {
        trace.record(
          SongsterrStage.songMeta,
          failure: SongsterrFailure.revisionUnavailable,
        );
        throw SongsterrException(SongsterrFailure.revisionUnavailable);
      }
      trace.revisionId = revisionId;
      final tracks = <SongsterrTrackMetadata>[];
      for (var index = 0; index < rawTracks.length; index++) {
        final raw = rawTracks[index];
        if (raw is! Map) continue;
        // Current metadata omits partId. The frontend assigns the ORIGINAL
        // zero-based array index, before excluding vocals/drums/other tracks.
        final partId = (raw['partId'] as num?)?.toInt() ?? index;
        if (raw['isDrums'] == true ||
            raw['isEmpty'] == true ||
            raw['isVocalTrack'] == true) {
          continue;
        }
        final name = (raw['name'] ?? raw['title'] ?? 'Track').toString();
        final instrument = (raw['instrument'] ?? name).toString();
        final instrumentId = (raw['instrumentId'] as num?)?.toInt();
        final label = instrument.toLowerCase();
        if (!(instrumentId != null &&
                instrumentId >= 24 &&
                instrumentId <= 39) &&
            !label.contains('guitar') &&
            !label.contains('bass')) {
          continue;
        }
        tracks.add(
          SongsterrTrackMetadata(
            partId: partId,
            name: name,
            instrument: instrument,
            tuningMidi: _intList(raw['tuning']),
            capo: (raw['capo'] as num?)?.toInt() ?? 0,
            hash: raw['hash'] as String?,
          ),
        );
      }
      trace.record(
        SongsterrStage.trackDiscovery,
        result: '${tracks.length} playable / ${rawTracks.length} total tracks',
        failure: tracks.isEmpty ? SongsterrFailure.noTracks : null,
      );
      if (tracks.isEmpty) throw SongsterrException(SongsterrFailure.noTracks);
      return SongsterrSongData(
        songId: songId,
        revisionId: revisionId,
        image: image ?? '',
        title: (json['title'] ?? 'Song').toString(),
        artist: (json['artist'] ?? 'Unknown artist').toString(),
        bpm: (json['bpm'] as num?)?.round(),
        source: json['source'] as String?,
        tracks: tracks,
      );
    } on TabProviderException {
      rethrow;
    } on Object {
      trace.record(
        SongsterrStage.songMeta,
        failure: SongsterrFailure.metaParseError,
      );
      throw SongsterrException(SongsterrFailure.metaParseError);
    }
  }

  /// Revision history is optional, and its first entry may be rejected or
  /// pending. Only the canonical current revision can supply the original GP.
  Future<String?> revisionSource(
    SongsterrSongData song,
    SongsterrDiagnostics trace,
  ) async {
    if (song.source?.isNotEmpty == true) return song.source;
    try {
      final response = await request(
        Uri.parse('$baseUrl/api/meta/${song.songId}/revisions'),
        SongsterrStage.revisionMeta,
        trace,
      );
      if (response.statusCode != 200) {
        throw SongsterrException(SongsterrFailure.revisionUnavailable);
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) throw const FormatException();
      for (final revision in decoded) {
        if (revision is Map &&
            revision['revisionId']?.toString() == song.revisionId) {
          final source = revision['source'];
          if (source is String && source.isNotEmpty) return source;
        }
      }
      trace.record(
        SongsterrStage.gpSource,
        failure: SongsterrFailure.gpSourceUnavailable,
      );
    } on Object {
      trace.record(
        SongsterrStage.revisionMeta,
        failure: SongsterrFailure.revisionUnavailable,
      );
    }
    return null;
  }

  Future<SongsterrTrackData> fetchTrack(
    SongsterrSongData song,
    SongsterrTrackMetadata track, {
    SongsterrDiagnostics? diagnostics,
  }) async {
    final trace = diagnostics ?? SongsterrDiagnostics(songId: song.songId);
    trace.partId = track.partId;
    // Verified in Songsterr's production frontend on 2026-09-26. Stage URLs
    // are ONLY for -stage images; legacy no-image revisions use /part/.
    final hosts = song.image.isEmpty
        ? const [
            'https://d3rrfvx08uyjp1.cloudfront.net',
            'https://dodkcbujl0ebx.cloudfront.net',
            'https://dj1usja78sinh.cloudfront.net',
          ]
        : song.image.endsWith('-stage')
        ? const ['https://d3d3l6a6rcgkaf.cloudfront.net']
        : cdnHosts;
    final ordered = [
      if (hosts.contains(_workingHost)) _workingHost!,
      ...hosts.where((host) => host != _workingHost),
    ];
    var failure = SongsterrFailure.trackJsonUnavailable;
    for (final host in ordered) {
      final uri = Uri.parse(
        song.image.isEmpty
            ? '$host/part/${song.revisionId}/${track.partId}'
            : '$host/${song.songId}/${song.revisionId}/${song.image}/${track.partId}.json',
      );
      try {
        final response = await request(uri, SongsterrStage.trackJson, trace);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          failure = SongsterrFailure.trackJsonUnavailable;
          trace.record(SongsterrStage.trackJson, failure: failure);
          continue;
        }
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json is! Map<String, dynamic> || json['measures'] is! List) {
          throw const FormatException();
        }
        if ((json['partId'] != null && json['partId'] != track.partId) ||
            (json['revisionId'] != null &&
                json['revisionId'].toString() != song.revisionId)) {
          throw const FormatException();
        }
        trace.record(
          SongsterrStage.structuredParse,
          result: '${(json['measures'] as List).length} measures',
        );
        _workingHost = host;
        return SongsterrTrackData(metadata: track, payload: json);
      } on SongsterrException catch (error) {
        failure = error.failure;
      } on Object {
        trace.record(
          SongsterrStage.structuredParse,
          failure: SongsterrFailure.trackJsonParseFailed,
        );
        throw SongsterrException(SongsterrFailure.trackJsonParseFailed);
      }
    }
    throw SongsterrException(failure);
  }

  static List<int> _intList(Object? value) => value is List
      ? value.whereType<num>().map((item) => item.toInt()).toList()
      : const [];
}

class SongsterrTrackConverter {
  const SongsterrTrackConverter();

  SavedTab convert({
    required SongsterrSongData song,
    required SongsterrTrackData track,
    required String sourceUrl,
  }) {
    try {
      return _convert(song: song, track: track, sourceUrl: sourceUrl);
    } on Object {
      throw SongsterrException(SongsterrFailure.structuredConversionFailed);
    }
  }

  SavedTab _convert({
    required SongsterrSongData song,
    required SongsterrTrackData track,
    required String sourceUrl,
  }) {
    final payload = track.payload;
    final tuningMidi = _intList(payload['tuning']).isNotEmpty
        ? _intList(payload['tuning'])
        : track.metadata.tuningMidi;
    if (tuningMidi.isEmpty ||
        tuningMidi.any((pitch) => pitch < 0 || pitch > 127)) {
      throw const TabProviderException(
        'Songsterr track tuning is unavailable.',
      );
    }
    final tuning = tuningMidi.reversed.map(_midiToName).toList();
    final measures = <TabMeasure>[];
    var numerator = 4;
    var denominator = 4;
    final rawMeasures = payload['measures'] as List;
    for (
      var measureIndex = 0;
      measureIndex < rawMeasures.length;
      measureIndex++
    ) {
      final raw = rawMeasures[measureIndex];
      if (raw is! Map) throw const FormatException();
      final signature = _intList(raw['signature']);
      if (raw['signature'] != null &&
          (signature.length != 2 || signature.any((n) => n <= 0))) {
        throw const FormatException();
      }
      if (signature.length >= 2 && signature[0] > 0 && signature[1] > 0) {
        numerator = signature[0];
        denominator = signature[1];
      }
      final beats = <TabBeat>[];
      final voices = raw['voices'];
      if (voices is List) {
        for (final voice in voices) {
          if (voice is! Map) throw const FormatException();
          var position = 0.0;
          final rawBeats = voice['beats'];
          if (rawBeats is! List) throw const FormatException();
          for (final rawBeat in rawBeats) {
            if (rawBeat is! Map) throw const FormatException();
            final duration = _duration(rawBeat);
            if (!duration.isFinite || duration <= 0) {
              throw const FormatException();
            }
            final notes = <TabNote>[];
            var meaningful = rawBeat['rest'] == true;
            if (rawBeat['rest'] != true && rawBeat['notes'] is List) {
              for (final rawNote in rawBeat['notes'] as List) {
                if (rawNote is! Map) throw const FormatException();
                if (rawNote['rest'] == true) {
                  meaningful = true;
                  continue;
                }
                final stringIndex = (rawNote['string'] as num?)?.toInt();
                final fret = (rawNote['fret'] as num?)?.toInt();
                if (stringIndex == null ||
                    stringIndex < 0 ||
                    stringIndex >= tuningMidi.length) {
                  throw const FormatException();
                }
                // Dead strokes without a fret are unpitched, not open strings.
                if (fret == null && rawNote['dead'] == true) {
                  meaningful = true;
                  continue;
                }
                if (fret == null || fret < 0) throw const FormatException();
                meaningful = true;
                notes.add(
                  TabNote(
                    stringNumber: stringIndex + 1,
                    fret: fret,
                    midiPitch: tuningMidi[stringIndex] + fret,
                    duration: duration,
                  ),
                );
              }
            }
            if (!meaningful) throw const FormatException();
            beats.add(
              TabBeat(
                position: position,
                duration: duration,
                notes: notes,
                isRest: notes.isEmpty,
              ),
            );
            position += duration;
          }
        }
      }
      beats.sort((a, b) => a.position.compareTo(b.position));
      if (beats.isEmpty) {
        if (raw['rest'] != true) throw const FormatException();
        beats.add(
          TabBeat(
            position: 0,
            duration: numerator * 4 / denominator,
            isRest: true,
          ),
        );
      }
      // Parallel voices share a timeline, not consecutive playback slots.
      final merged = <TabBeat>[];
      for (final beat in beats) {
        if (merged.isNotEmpty &&
            (merged.last.position - beat.position).abs() < 0.000001) {
          final previous = merged.removeLast();
          merged.add(
            TabBeat(
              position: previous.position,
              duration: previous.duration > beat.duration
                  ? previous.duration
                  : beat.duration,
              notes: [...previous.notes, ...beat.notes],
              isRest: previous.isRest && beat.isRest,
            ),
          );
        } else {
          merged.add(beat);
        }
      }
      final end = beats
          .map((beat) => beat.position + beat.duration)
          .reduce((a, b) => a > b ? a : b);
      final timeline = [
        for (var i = 0; i < merged.length; i++)
          TabBeat(
            position: merged[i].position,
            duration:
                (i + 1 < merged.length ? merged[i + 1].position : end) -
                merged[i].position,
            notes: merged[i].notes,
            isRest: merged[i].isRest,
          ),
      ];
      measures.add(
        TabMeasure(
          number: measureIndex + 1,
          numerator: numerator,
          denominator: denominator,
          beats: timeline,
        ),
      );
    }
    if (measures.isEmpty) {
      throw const TabProviderException('Songsterr track contains no measures.');
    }
    final instrumentLabel = track.metadata.instrument.toLowerCase();
    final instrument = instrumentLabel.contains('bass')
        ? InstrumentType.bass
        : instrumentLabel.contains('guitar')
        ? InstrumentType.guitar
        : InstrumentType.other;
    final bpm = _tempo(payload) ?? song.bpm;
    return SavedTab(
      title: song.title,
      artist: song.artist,
      source: 'Songsterr',
      sourceUrl: sourceUrl,
      sourceId: song.songId,
      tabType: instrument == InstrumentType.bass
          ? TabType.bass
          : TabType.guitarPro,
      trackName: track.metadata.name,
      instrument: instrument,
      stringCount: tuning.length,
      tuning: tuning,
      capo: (payload['capo'] as num?)?.toInt() ?? track.metadata.capo,
      bpm: bpm,
      measures: measures,
      sourceData: jsonEncode({
        'revisionId': song.revisionId,
        'partId': track.metadata.partId,
        if (track.metadata.hash != null) 'trackHash': track.metadata.hash,
        if (payload['automations'] != null)
          'automations': payload['automations'],
        'measureRepeats': [
          for (final raw in rawMeasures)
            if (raw is Map)
              {
                for (final key in raw.keys)
                  if (key.toString().toLowerCase().contains('repeat'))
                    key.toString(): raw[key],
              },
        ],
      }),
    );
  }

  static double _duration(Map beat) {
    final fraction = beat['duration'];
    double value;
    if (fraction is List && fraction.length >= 2) {
      final top = fraction[0] as num?;
      final bottom = fraction[1] as num?;
      if (top == null || bottom == null || bottom <= 0) {
        throw const FormatException();
      }
      // Songsterr's rational duration ALREADY includes dots and tuplets.
      return top.toDouble() / bottom.toDouble() * 4;
    } else {
      final type = (beat['type'] as num?)?.toDouble();
      if (type == null || type <= 0) throw const FormatException();
      value = 4 / type;
    }
    final dots = (beat['dots'] as num?)?.toInt() ?? 0;
    var addition = value / 2;
    for (var index = 0; index < dots; index++) {
      value += addition;
      addition /= 2;
    }
    final tuplet = (beat['tuplet'] as num?)?.toInt();
    if (tuplet != null && tuplet > 1) {
      const normalCounts = {
        3: 2,
        5: 4,
        6: 4,
        7: 4,
        9: 8,
        10: 8,
        11: 8,
        12: 8,
        13: 8,
      };
      final normal = normalCounts[tuplet];
      if (normal == null) throw const FormatException();
      value *= normal / tuplet;
    }
    return value;
  }

  static int? _tempo(Map<String, dynamic> payload) {
    final automations = payload['automations'];
    if (automations is! Map || automations['tempo'] is! List) return null;
    for (final item in automations['tempo'] as List) {
      if (item is Map && item['bpm'] is num) {
        return (item['bpm'] as num).round();
      }
    }
    return null;
  }

  static List<int> _intList(Object? value) => value is List
      ? value.whereType<num>().map((item) => item.toInt()).toList()
      : const [];
}

String _midiToName(int midi) =>
    '${const ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][midi % 12]}${midi ~/ 12 - 1}';
