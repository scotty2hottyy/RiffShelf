import '../../../core/models/instrument_type.dart';
import '../../../core/models/saved_tab.dart';

/// What the user typed in Discover, plus optional filters.
class TabSearchQuery {
  const TabSearchQuery({required this.text, this.instrument, this.type});
  final String text;
  final InstrumentType? instrument;
  final TabType? type;
}

/// One song and instrument returned by a search provider.
///
/// [externalId] is the provider's own id and is used when downloading.
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
    this.availableArrangements = const [],
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
  final List<TabArrangement> availableArrangements;
}

/// A named track within a search result, such as one guitar part.
class TabArrangement {
  const TabArrangement({this.name, this.tuning});
  final String? name;
  final List<String>? tuning;
}

/// Broad cause of a [TabProviderException], used to pick an error message.
enum TabProviderErrorKind { network, timeout, http, malformed, unknown }

/// Error raised by a provider for network, timeout, or bad-data failures.
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

/// A downloadable track the user can choose when a song has several.
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

/// Thrown by a provider when the user must choose one of [options] before
/// the tab can be downloaded.
class TabTrackSelectionException implements Exception {
  const TabTrackSelectionException(this.options);
  final List<TabTrackOption> options;
}

/// A provider that can download a specific [TabTrackOption].
abstract interface class TrackSelectableTabSourceProvider {
  Future<SavedTab> fetchTabTrack(TabSearchResult result, TabTrackOption option);
}

/// A provider that keeps a short, privacy-safe log for bug reports.
abstract interface class DiagnosticTabSourceProvider {
  String diagnosticReport(String sourceId);
  void recordDisplay(String sourceId);
}

/// A provider that can download a saved tab again from its source,
/// matching the originally selected track.
abstract interface class RecoverableTabSourceProvider {
  Future<SavedTab> retrySavedTab(SavedTab existing);
}

/// Website-independent boundary for future online tab integrations.
abstract interface class TabSearchProvider {
  Future<List<TabSearchResult>> search(TabSearchQuery query);
}

/// A provider that can both search and download tabs.
abstract interface class TabSourceProvider implements TabSearchProvider {
  String get name;
  Future<SavedTab> fetchTab(TabSearchResult result);
}
