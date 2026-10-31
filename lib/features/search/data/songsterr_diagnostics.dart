import '../domain/tab_source_provider.dart';

enum SongsterrStage {
  search,
  songMeta,
  trackDiscovery,
  revisionMeta,
  gpSource,
  trackJson,
  structuredParse,
  modelConversion,
  display,
}

enum SongsterrFailure {
  networkUnreachable,
  timeout,
  httpError,
  metaParseError,
  noTracks,
  revisionUnavailable,
  gpSourceUnavailable,
  gpParseFailed,
  trackJsonUnavailable,
  trackJsonParseFailed,
  structuredConversionFailed,
  noUsableContent,
}

class SongsterrException extends TabProviderException {
  SongsterrException(this.failure, {String? message})
    : super(
        message ??
            switch (failure) {
              SongsterrFailure.networkUnreachable =>
                'You appear to be offline.',
              SongsterrFailure.timeout =>
                'Songsterr took too long to respond. Try again.',
              SongsterrFailure.metaParseError ||
              SongsterrFailure.revisionUnavailable =>
                'Song information could not be loaded.',
              SongsterrFailure.noTracks =>
                'No playable guitar or bass tracks were found.',
              _ => 'Tab data could not be downloaded for this version.',
            },
        kind: switch (failure) {
          SongsterrFailure.networkUnreachable => TabProviderErrorKind.network,
          SongsterrFailure.timeout => TabProviderErrorKind.timeout,
          SongsterrFailure.httpError ||
          SongsterrFailure.trackJsonUnavailable => TabProviderErrorKind.http,
          SongsterrFailure.metaParseError ||
          SongsterrFailure.trackJsonParseFailed ||
          SongsterrFailure.structuredConversionFailed =>
            TabProviderErrorKind.malformed,
          _ => TabProviderErrorKind.unknown,
        },
      );
  final SongsterrFailure failure;
}

/// Available in this personal Release build so device failures are actionable.
/// Reports contain only bounded, explicit fields, never bodies or exceptions.
class SongsterrDiagnostics {
  SongsterrDiagnostics({this.songId});
  String? songId;
  String? revisionId;
  int? partId;
  final List<String> _events = [];

  SongsterrDiagnostics forSong(String id) {
    final copy = SongsterrDiagnostics(songId: id);
    copy._events.addAll(_events.where((event) => event.startsWith('SEARCH')));
    return copy;
  }

  void record(
    SongsterrStage stage, {
    Uri? endpoint,
    int? status,
    int? bytes,
    String? contentType,
    String? result,
    SongsterrFailure? failure,
  }) {
    final name = stage.name
        .replaceAllMapped(RegExp(r'[A-Z]'), (match) => '_${match[0]}')
        .toUpperCase();
    final fields = [
      name,
      if (endpoint != null) '${endpoint.host}${endpoint.path}',
      if (status != null) 'HTTP $status',
      if (bytes != null) '$bytes bytes',
      if (contentType != null) contentType.split(';').first,
      ?result,
      if (failure != null)
        'failure=${failure.name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}',
    ];
    _events.add(
      fields.join(' | ').replaceAll(RegExp(r'[\r\n]'), ' ').substringSafe(240),
    );
    if (_events.length > 32) _events.removeAt(0);
  }

  String get report => [
    'Songsterr Diagnostic',
    if (songId != null) 'Song ID: ${songId!.substringSafe(24)}',
    if (revisionId != null) 'Revision ID: ${revisionId!.substringSafe(24)}',
    if (partId != null) 'Track selected: $partId',
    ..._events,
  ].join('\n');
}

extension on String {
  String substringSafe(int length) =>
      this.length > length ? substring(0, length) : this;
}
