import '../../../core/models/instrument_type.dart';
import 'tab_source_provider.dart';

class SearchFilters {
  const SearchFilters({this.instrument, this.type, this.source});
  final InstrumentType? instrument;
  final TabType? type;
  final String? source;

  bool matches(TabSearchResult result) {
    if (instrument != null && result.instrument != instrument) return false;
    if (type != null && !result.availableTypes.contains(type)) return false;
    if (source != null && result.sourceName != source) return false;
    return true;
  }
}
