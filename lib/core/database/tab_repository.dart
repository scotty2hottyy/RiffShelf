import '../models/instrument_type.dart';
import '../models/saved_tab.dart';

class TabFilter {
  const TabFilter({
    this.query = '',
    this.instrument,
    this.tuning,
    this.tags = const {},
    this.favoritesOnly = false,
  });
  final String query;
  final InstrumentType? instrument;
  final List<String>? tuning;
  final Set<String> tags;
  final bool favoritesOnly;
}

abstract interface class TabRepository {
  Future<List<SavedTab>> findTabs([TabFilter filter = const TabFilter()]);
  Future<SavedTab?> getById(int id);
  Future<SavedTab> save(SavedTab tab);
  Future<Set<String>> allTags();
  Future<void> delete(int id);
  Future<void> close();
}
