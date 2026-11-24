import '../../../core/models/saved_tab.dart';
import '../../import/ascii_tab_parser.dart';
import '../domain/tab_source_provider.dart';

/// A search provider that failed, kept so the UI can report it.
class ProviderSearchFailure {
  const ProviderSearchFailure({required this.provider, required this.error});
  final String provider;
  final Object error;
}

/// Results from every provider that answered, plus the ones that failed.
class CombinedSearchResponse {
  const CombinedSearchResponse({required this.results, required this.failures});
  final List<TabSearchResult> results;
  final List<ProviderSearchFailure> failures;
}

/// Coordinates tab search and download across the configured providers.
///
/// When [searchProvider] is set (the optional backend), it handles search
/// and its errors are reported instead of falling back to [providers].
/// Downloads always go through the matching entry in [providers].
class TabSearchService {
  const TabSearchService(this.providers, {this.searchProvider});
  final List<TabSourceProvider> providers;
  final TabSearchProvider? searchProvider;

  /// Downloads [result] from its provider, optionally for one [track].
  ///
  /// Throws [TabProviderException] if the arrangement has no playable
  /// notes. The returned tab carries an `online:` import key so saving the
  /// same arrangement twice is detected as a duplicate.
  Future<SavedTab> fetch(
    TabSearchResult result, [
    TabTrackOption? track,
  ]) async {
    final provider = providers.firstWhere(
      (provider) => provider.name == result.sourceName,
    );
    final tab = track == null
        ? await provider.fetchTab(result)
        : await (provider as TrackSelectableTabSourceProvider).fetchTabTrack(
            result,
            track,
          );
    if (!tab.hasUsableContent ||
        !tab.measures.any((m) => m.beats.any((b) => b.notes.isNotEmpty)) &&
            !AsciiTabParser.hasNotes(tab.asciiTab)) {
      throw const TabProviderException(
        'This arrangement has no usable tablature.',
      );
    }
    return tab.copyWith(
      importKey:
          'online:${result.sourceName}:${result.externalId}:${track?.id ?? tab.trackName ?? "default"}',
    );
  }

  /// Searches every provider. A failing provider does not hide results
  /// from the others; it is listed in [CombinedSearchResponse.failures].
  Future<CombinedSearchResponse> search(TabSearchQuery query) async {
    if (searchProvider case final provider?) {
      try {
        return CombinedSearchResponse(
          results: (await provider.search(query))
              .where(
                (result) =>
                    (query.instrument == null ||
                        result.instrument == query.instrument) &&
                    (query.type == null ||
                        result.availableTypes.contains(query.type)),
              )
              .toList(),
          failures: const [],
        );
      } on Object catch (error) {
        return CombinedSearchResponse(
          results: const [],
          failures: [ProviderSearchFailure(provider: 'Backend', error: error)],
        );
      }
    }
    final batches = await Future.wait(
      providers.map((provider) async {
        try {
          return (
            provider: provider.name,
            results: await provider.search(query),
            error: null,
          );
        } on Object catch (error) {
          return (
            provider: provider.name,
            results: <TabSearchResult>[],
            error: error,
          );
        }
      }),
    );
    return CombinedSearchResponse(
      results: [for (final batch in batches) ...batch.results],
      failures: [
        for (final batch in batches)
          if (batch.error != null)
            ProviderSearchFailure(
              provider: batch.provider,
              error: batch.error!,
            ),
      ],
    );
  }
}
