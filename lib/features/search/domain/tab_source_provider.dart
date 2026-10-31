import '../../../core/models/instrument_type.dart';
import '../../../core/models/saved_tab.dart';

class TabSearchQuery {
  const TabSearchQuery({required this.text, this.instrument, this.type});
  final String text;
  final InstrumentType? instrument;
  final TabType? type;
}

class TabSearchResult {
  const TabSearchResult({
    required this.externalId,
    required this.title,
    required this.artist,
    required this.instrument,
    required this.sourceName,
    required this.sourceUrl,
    this.availableTypes = const [],
    this.type = TabType.tab,
    this.tuning,
    this.stringCount,
  });
  final String externalId;
  final String title;
  final String artist;
  final InstrumentType instrument;
  final String sourceName;
  final String sourceUrl;
  final List<TabType> availableTypes;
  final TabType type;
  final List<String>? tuning;
  final int? stringCount;
}

enum TabProviderErrorKind { network, timeout, http, malformed, unknown }

class TabProviderException implements Exception {
  const TabProviderException(
    this.message, {
    this.kind = TabProviderErrorKind.unknown,
    this.cause,
  });
  final String message;
  final TabProviderErrorKind kind;
  final Object? cause;

  @override
  String toString() => message;
}

class TabTrackOption {
  const TabTrackOption({
    required this.id,
    required this.name,
    required this.instrument,
    this.tuning = const [],
  });
  final String id;
  final String name;
  final String instrument;
  final List<String> tuning;
}

class TabTrackSelectionException implements Exception {
  const TabTrackSelectionException(this.options);
  final List<TabTrackOption> options;
}

abstract interface class TrackSelectableTabSourceProvider {
  Future<SavedTab> fetchTabTrack(TabSearchResult result, TabTrackOption option);
}

abstract interface class DiagnosticTabSourceProvider {
  String diagnosticReport(String sourceId);
  void recordDisplay(String sourceId);
}

abstract interface class RecoverableTabSourceProvider {
  Future<SavedTab> retrySavedTab(SavedTab existing);
}

/// Website-independent boundary for future online tab integrations.
abstract interface class TabSourceProvider {
  String get name;
  Future<List<TabSearchResult>> search(TabSearchQuery query);
  Future<SavedTab> fetchTab(TabSearchResult result);
}
