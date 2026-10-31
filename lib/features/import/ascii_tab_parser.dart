import '../../core/models/instrument_type.dart';

class AsciiTabInference {
  const AsciiTabInference({
    required this.instrument,
    required this.tuning,
    required this.type,
  });
  final InstrumentType instrument;
  final List<String> tuning;
  final TabType type;
  int get stringCount => tuning.length;
}

abstract final class AsciiTabParser {
  static final _linePattern = RegExp(
    r'^\s*([A-Ga-g](?:#|b)?)?\s*\|[-|0-9xXhHpPbBrRsS/\\~(). ]+\|?\s*$',
  );

  static bool hasNotes(String content) => content
      .split('\n')
      .any(
        (line) => _linePattern.hasMatch(line) && RegExp(r'\d').hasMatch(line),
      );

  static bool isMalformed(String content) {
    final hasTabSignals = content.contains('|') || content.contains('--');
    if (!hasTabSignals) return false;
    return content
            .split('\n')
            .where((line) => _linePattern.hasMatch(line))
            .length <
        2;
  }

  static AsciiTabInference infer(String content) {
    final notes = <String>[];
    for (final line in content.split('\n')) {
      final match = _linePattern.firstMatch(line);
      if (match != null) {
        notes.add((match.group(1) ?? '').toUpperCase());
      } else if (notes.isNotEmpty) {
        break;
      }
    }
    if (notes.length == 4) {
      final tuning = notes.reversed
          .map((note) => note.isEmpty ? '?' : note)
          .toList();
      return AsciiTabInference(
        instrument: InstrumentType.other,
        tuning: tuning,
        type: TabType.bass,
      );
    }
    if (notes.length >= 2) {
      final tuning = notes.reversed
          .map((note) => note.isEmpty ? '?' : note)
          .toList();
      return AsciiTabInference(
        instrument: InstrumentType.other,
        tuning: tuning,
        type: TabType.tab,
      );
    }
    return AsciiTabInference(
      instrument: InstrumentType.other,
      tuning: const ['?', '?', '?', '?', '?', '?'],
      type: TabType.chords,
    );
  }
}
