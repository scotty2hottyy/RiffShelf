import '../models/instrument_type.dart';
import '../models/saved_tab.dart';

/// Criteria for [TabRepository.findTabs].
///
/// Every field is optional. Unset fields do not filter, and set fields are
/// combined with AND. [query] matches against title and artist.
class TabFilter {
  const TabFilter({
    this.query = '',
    this.instrument,
    this.classification,
    this.stringCount,
    this.tuning,
    this.tags = const {},
    this.favoritesOnly = false,
  });
  final String query;
  final InstrumentType? instrument;
  final InstrumentClassification? classification;
  final int? stringCount;
  final List<String>? tuning;
  final Set<String> tags;
  final bool favoritesOnly;
}

/// Thrown by [TabRepository.save] when a tab with the same import key is
/// already in the library.
class DuplicateTabException implements Exception {
  const DuplicateTabException();
}

/// Storage for the user's saved tabs.
///
/// The app uses `SqliteTabRepository`; tests can use an in-memory database
/// or a fake that implements this interface.
abstract interface class TabRepository {
  /// Returns saved tabs that match [filter].
  Future<List<SavedTab>> findTabs([TabFilter filter = const TabFilter()]);

  /// Returns the tab with [id], or null if it does not exist.
  Future<SavedTab?> getById(int id);

  /// Inserts [tab] if it has no id, otherwise updates it.
  ///
  /// Returns the stored tab with its id set. Throws [ArgumentError] if the
  /// tab has no usable content and [DuplicateTabException] if its import
  /// key is already saved.
  Future<SavedTab> save(SavedTab tab);

  /// Returns every tag used by at least one saved tab.
  Future<Set<String>> allTags();

  /// Deletes the tab with [id].
  Future<void> delete(int id);

  /// Releases the underlying database connection.
  Future<void> close();
}

/// Optional atomic artwork update used by background matching.
abstract interface class AutomaticArtworkRepository {
  Future<bool> setArtworkIfUnselected({
    required int id,
    required String artist,
    required String title,
    required String artwork,
  });
}
