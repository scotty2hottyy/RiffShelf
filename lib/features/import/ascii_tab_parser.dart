import '../../core/models/instrument_type.dart';
import '../../core/models/tab_structure.dart';

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

  /// Extracts fret columns for approximate scrolling only, never authored rhythm.
  static List<TabMeasure> approximateMeasures(String content, int stringCount) {
    if (stringCount < 1) return const [];
    final measures = <TabMeasure>[];
    final rows = <String>[];
    final fretPattern = RegExp(r'\d+');

    void flush() {
      for (
        var first = 0;
        first + stringCount <= rows.length;
        first += stringCount
      ) {
        final columns = <int, List<TabNote>>{};
        for (var string = 0; string < stringCount; string++) {
          final row = rows[first + string];
          for (final match in fretPattern.allMatches(row)) {
            final fret = int.tryParse(match.group(0)!);
            if (fret == null) continue;
            (columns[match.start] ??= []).add(
              TabNote(stringNumber: string + 1, fret: fret),
            );
          }
        }
        final positions = columns.keys.toList()..sort();
        for (var offset = 0; offset < positions.length; offset += 4) {
          measures.add(
            TabMeasure(
              number: measures.length + 1,
              beats: [
                for (
                  var i = offset;
                  i < positions.length && i < offset + 4;
                  i++
                )
                  TabBeat(
                    position: (i - offset).toDouble(),
                    notes: columns[positions[i]]!,
                  ),
              ],
            ),
          );
        }
      }
      rows.clear();
    }

    for (final line in content.split('\n')) {
      if (_linePattern.hasMatch(line)) {
        rows.add(line.substring(line.indexOf('|') + 1).trimRight());
      } else {
        flush();
      }
    }
    flush();
    return measures;
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
