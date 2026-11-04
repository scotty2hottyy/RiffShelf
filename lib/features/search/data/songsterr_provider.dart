import 'dart:convert';

import 'package:dart_gp_tab_reader/dart_gp_tab_reader.dart' as gp;
import 'package:http/http.dart' as http;

import '../../../core/models/instrument_type.dart';
import '../../../core/models/saved_tab.dart';
import '../../import/guitar_pro_importer.dart';
import '../domain/tab_source_provider.dart';
import 'songsterr_diagnostics.dart';
import 'songsterr_structured_client.dart';

class SongsterrProvider
    implements
        TabSourceProvider,
        TrackSelectableTabSourceProvider,
        DiagnosticTabSourceProvider,
        RecoverableTabSourceProvider {
  SongsterrProvider({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    SongsterrStructuredClient? structuredClient,
    GuitarProImporter? importer,
  }) : _importer = importer ?? const GuitarProImporter(),
       _structuredClient =
           structuredClient ??
           SongsterrStructuredClient(
             client: client ?? http.Client(),
             timeout: timeout,
           );

  static const _baseUrl = 'https://www.songsterr.com';
  final GuitarProImporter _importer;
  final SongsterrStructuredClient _structuredClient;
  final Duration timeout;
  final Map<String, SongsterrSongData> _songCache = {};
  final Map<String, SongsterrDiagnostics> _traces = {};
  SongsterrDiagnostics _searchTrace = SongsterrDiagnostics();

  @override
  String get name => 'Songsterr';

  @override
  String diagnosticReport(String sourceId) =>
      (_traces[sourceId] ?? _traces[_songId('', sourceId)] ?? _searchTrace)
          .report;

  static String _songId(String? id, String sourceUrl) {
    if (id != null && RegExp(r'^\d+$').hasMatch(id)) return id;
    final uri = Uri.tryParse(sourceUrl);
    return uri?.queryParameters['id'] ??
        RegExp(r'-s(\d+)').firstMatch(uri?.path ?? '')?.group(1) ??
        '';
  }

  @override
  void recordDisplay(String sourceId) {
    final trace = _traces[sourceId];
    if (trace != null && !trace.report.contains('DISPLAY')) {
      trace.record(
        SongsterrStage.display,
        result: 'structured/text content ready',
      );
    }
  }

  @override
  Future<List<TabSearchResult>> search(TabSearchQuery query) async {
    if (query.text.trim().isEmpty) return [];
    _searchTrace = SongsterrDiagnostics();
    final legacy = Uri.parse('$_baseUrl/a/ra/songs.json')
        .replace(queryParameters: {'pattern': query.text.trim()});
    final modern = Uri.parse('$_baseUrl/api/songs')
        .replace(queryParameters: {'pattern': query.text.trim(), 'size': '50'});
    http.Response? response;
    String primaryOutcome = 'request failed';
    try {
      response = await _structuredClient.request(
        modern,
        SongsterrStage.search,
        _searchTrace,
      );
      primaryOutcome = 'HTTP ${response.statusCode}';
    } on SongsterrException catch (error) {
      primaryOutcome = error.failure.name;
      // A failed search request can use the legacy endpoint. Tab downloads
      // still use their own structured metadata and track endpoints.
    }
    if (response == null ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      response = await _structuredClient.request(
        legacy,
        SongsterrStage.search,
        _searchTrace,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _searchTrace.record(
        SongsterrStage.search,
        failure: SongsterrFailure.httpError,
      );
      throw SongsterrException(
        SongsterrFailure.httpError,
        message:
            'Songsterr is temporarily unavailable '
            '(search: $primaryOutcome; fallback: HTTP ${response.statusCode}).',
      );
    }
    try {
      final results = parseSearchResponse(utf8.decode(response.bodyBytes));
      _searchTrace.record(
        SongsterrStage.search,
        result: '${results.length} results',
      );
      return results
          .where(
            (result) =>
                (query.instrument == null ||
                    result.instrument == query.instrument) &&
                (query.type == null ||
                    result.availableTypes.contains(query.type)),
          )
          .toList();
    } on Object {
      _searchTrace.record(
        SongsterrStage.search,
        result: 'malformed search response',
      );
      throw const TabProviderException(
        'Songsterr returned malformed search results.',
        kind: TabProviderErrorKind.malformed,
      );
    }
  }

  static List<TabSearchResult> parseSearchResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const FormatException('Expected a list');
      }
      return decoded.expand((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid song entry');
        }
        return _parseSongs(item);
      }).toList();
    } on Object catch (error) {
      throw TabProviderException(
        'Songsterr returned malformed data.',
        kind: TabProviderErrorKind.malformed,
        cause: error,
      );
    }
  }

  static List<TabSearchResult> _parseSongs(Map<String, dynamic> song) {
    final id = (song['id'] ?? song['songId'])?.toString();
    final title = song['title']?.toString();
    final artistValue = song['artist'];
    final artist = artistValue is Map
        ? artistValue['name']?.toString()
        : artistValue?.toString();
    if (id == null ||
        !RegExp(r'^\d+$').hasMatch(id) ||
        title == null ||
        title.trim().isEmpty ||
        artist == null) {
      throw const FormatException('Missing required song fields');
    }

    final instruments = <InstrumentType>{};
    void collect(dynamic value) {
      if (value is String) {
        final label = value.toLowerCase();
        if (label.contains('guitar')) instruments.add(InstrumentType.guitar);
        if (RegExp(r'\bbass\b').hasMatch(label)) {
          instruments.add(InstrumentType.bass);
        }
      }
      if (value is Map) {
        final id = value['instrumentId'];
        if (id is num && id >= 24 && id <= 31) {
          instruments.add(InstrumentType.guitar);
        } else if (id is num && id >= 32 && id <= 39) {
          instruments.add(InstrumentType.bass);
        } else if (id == null) {
          collect(
            value['instrument'] ??
                value['name'] ??
                value['title'] ??
                value['type'],
          );
        }
      }
    }

    collect(song['defaultTrack']);
    final tracks = song['tracks'];
    if (tracks is List) {
      for (final track in tracks) {
        collect(track);
      }
    }
    if (instruments.isEmpty) instruments.add(InstrumentType.other);
    return [
      for (final instrument in instruments)
        TabSearchResult(
          externalId: id,
          title: title,
          artist: artist,
          instrument: instrument,
          sourceName: 'Songsterr',
          sourceUrl: '$_baseUrl/a/wsa/song?id=$id',
          availableTypes: [
            instrument == InstrumentType.bass
                ? TabType.bass
                : TabType.guitarPro,
          ],
          type: instrument == InstrumentType.bass
              ? TabType.bass
              : TabType.guitarPro,
        ),
    ];
  }

  SongsterrDiagnostics _newTrace(String id) =>
      _traces[id] = _searchTrace.forSong(id);

  Future<SongsterrSongData> _loadSong(String id) async {
    final song = await _structuredClient.fetchSong(
      id,
      diagnostics: _newTrace(id),
    );
    _songCache[id] = song;
    return song;
  }

  TabTrackOption _option(SongsterrTrackMetadata track) => TabTrackOption(
    id: 'json:${track.partId}',
    name: track.name,
    instrument: track.instrument,
    tuning: track.tuning,
  );

  @override
  Future<SavedTab> fetchTab(TabSearchResult result) async {
    final song = await _loadSong(result.externalId);
    final tracks = song.tracks
        .where(
          (track) =>
              result.instrument == InstrumentType.other ||
              (result.instrument == InstrumentType.bass
                  ? track.instrument.toLowerCase().contains('bass')
                  : track.instrument.toLowerCase().contains('guitar')),
        )
        .toList();
    if (tracks.isEmpty) throw SongsterrException(SongsterrFailure.noTracks);
    if (tracks.length > 1) {
      throw TabTrackSelectionException(tracks.map(_option).toList());
    }
    return _fetchTrack(result, song, tracks.single);
  }

  @override
  Future<SavedTab> fetchTabTrack(
    TabSearchResult result,
    TabTrackOption option,
  ) async {
    if (!RegExp(r'^\d+$').hasMatch(result.externalId)) {
      result = TabSearchResult(
        externalId: _songId(null, result.sourceUrl),
        title: result.title,
        artist: result.artist,
        instrument: result.instrument,
        sourceName: name,
        sourceUrl: result.sourceUrl,
      );
    }
    final song =
        _songCache[result.externalId] ?? await _loadSong(result.externalId);
    final id = int.tryParse(option.id.replaceFirst('json:', ''));
    final matches = song.tracks.where((track) => track.partId == id);
    if (matches.isEmpty) throw SongsterrException(SongsterrFailure.noTracks);
    return _fetchTrack(result, song, matches.first);
  }

  Future<SavedTab> _fetchTrack(
    TabSearchResult result,
    SongsterrSongData song,
    SongsterrTrackMetadata metadata,
  ) async {
    final trace = _traces[result.externalId] ?? _newTrace(result.externalId);
    trace.partId = metadata.partId;
    final sourceData = jsonEncode({
      'revisionId': song.revisionId,
      'partId': metadata.partId,
      if (metadata.hash != null) 'trackHash': metadata.hash,
    });
    final source = await _structuredClient.revisionSource(song, trace);
    if (source != null) {
      try {
        final response = await _structuredClient.request(
          Uri.parse(source),
          SongsterrStage.gpSource,
          trace,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw SongsterrException(SongsterrFailure.gpSourceUnavailable);
        }
        final document = _importer.parse(response.bodyBytes);
        // Never silently substitute the first GP track for the selected part.
        final matches = document.tracks
            .where(
              (track) =>
                  track.name == metadata.name &&
                  (metadata.tuningMidi.isEmpty ||
                      track.stringCount == metadata.tuningMidi.length),
            )
            .toList();
        final candidate = matches.length == 1
            ? matches.single
            : document.tracks.length == 1 && song.tracks.length == 1
            ? document.tracks.single
            : null;
        if (candidate == null) throw const FormatException();
        // The general importer fills empty measures with rests. Validate actual
        // GP beats first so that cannot turn a metadata-only source into content.
        final original = document.song.tracks[candidate.index];
        if (!original.measures.any(
          (m) => m.voices.any(
            (v) => v.beats.any(
              (beat) =>
                  beat.notes.isNotEmpty || beat.status == gp.BeatStatus.rest,
            ),
          ),
        )) {
          throw const FormatException();
        }
        final imported = _importer
            .convert(
              document,
              trackIndex: candidate.index,
              sourceUrl: result.sourceUrl,
              source: name,
              sourceId: result.externalId,
            )
            .copyWithSourceData(sourceData);
        final tab = imported.withMetadata(
          title: song.title,
          artist: song.artist,
          trackName: metadata.name,
          instrument: metadata.instrument.toLowerCase().contains('bass')
              ? InstrumentType.bass
              : InstrumentType.guitar,
          tuning: imported.tuning,
          capo: imported.capo,
          bpm: imported.bpm,
          tags: imported.tags,
        );
        if (!tab.hasUsableContent) throw const FormatException();
        trace.record(
          SongsterrStage.gpSource,
          result:
              'parsed ${document.tracks.length} tracks; selected ${candidate.index}',
        );
        trace.record(
          SongsterrStage.modelConversion,
          result: 'GP: ${tab.measures.length} measures',
        );
        return tab;
      } on Object catch (error) {
        trace.record(
          SongsterrStage.gpSource,
          failure: error is SongsterrException
              ? error.failure
              : SongsterrFailure.gpParseFailed,
        );
        // An optional original file must never block the native JSON route.
      }
    }
    final track = await _structuredClient.fetchTrack(
      song,
      metadata,
      diagnostics: trace,
    );
    try {
      final tab = const SongsterrTrackConverter().convert(
        song: song,
        track: track,
        sourceUrl: result.sourceUrl,
      );
      if (!tab.hasUsableContent) {
        throw SongsterrException(SongsterrFailure.noUsableContent);
      }
      final notes = tab.measures.fold<int>(
        0,
        (sum, m) =>
            sum + m.beats.fold<int>(0, (sum, b) => sum + b.notes.length),
      );
      trace.record(
        SongsterrStage.modelConversion,
        result: '${tab.measures.length} measures, $notes notes',
      );
      return tab;
    } on Object catch (error) {
      final failure = error is SongsterrException
          ? error.failure
          : SongsterrFailure.structuredConversionFailed;
      trace.record(SongsterrStage.modelConversion, failure: failure);
      throw SongsterrException(failure);
    }
  }

  @override
  Future<SavedTab> retrySavedTab(SavedTab existing) async {
    final id = _songId(existing.sourceId, existing.sourceUrl);
    final result = TabSearchResult(
      externalId: id,
      title: existing.title,
      artist: existing.artist,
      instrument: existing.instrument,
      sourceName: name,
      sourceUrl: existing.sourceUrl,
    );
    final song = await _loadSong(id);
    Map identity = {};
    try {
      final decoded = jsonDecode(existing.sourceData ?? '{}');
      if (decoded is Map) identity = decoded;
    } on Object {
      /* Old or corrupt identity: let the user choose safely. */
    }
    final matches = song.tracks
        .where(
          (track) => identity['trackHash'] != null
              ? track.hash == identity['trackHash']
              : (identity['revisionId'] == null ||
                        identity['revisionId'].toString() == song.revisionId) &&
                    track.partId == identity['partId'],
        )
        .toList();
    if (matches.length == 1) return _fetchTrack(result, song, matches.single);
    if (song.tracks.length == 1) {
      return _fetchTrack(result, song, song.tracks.single);
    }
    throw TabTrackSelectionException(song.tracks.map(_option).toList());
  }
}
