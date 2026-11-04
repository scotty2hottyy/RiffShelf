import 'package:flutter/foundation.dart';

import 'instrument_type.dart';

@immutable
class TuningPreset {
  const TuningPreset({
    required this.name,
    required this.instrument,
    required this.notes,
  });
  final String name;
  final InstrumentType instrument;
  final List<String> notes;
  int get stringCount => notes.length;
}

abstract final class StandardTunings {
  static const guitarStandard = TuningPreset(
    name: 'Standard',
    instrument: InstrumentType.guitar,
    notes: ['E', 'A', 'D', 'G', 'B', 'E'],
  );
  static const bassStandard = TuningPreset(
    name: 'Standard',
    instrument: InstrumentType.bass,
    notes: ['E', 'A', 'D', 'G'],
  );
  static const guitarDropD = TuningPreset(
    name: 'Drop D',
    instrument: InstrumentType.guitar,
    notes: ['D', 'A', 'D', 'G', 'B', 'E'],
  );
  static const all = [guitarStandard, bassStandard, guitarDropD];

  static TuningPreset? infer(List<String> notes, {InstrumentType? instrument}) {
    final normalized = notes.map((note) => note.trim().toUpperCase()).toList();
    for (final preset in all) {
      if (instrument != null && preset.instrument != instrument) continue;
      if (listEquals(preset.notes, normalized)) return preset;
    }
    return null;
  }

  static String keyFor(List<String> notes) =>
      notes.map((note) => note.trim().toUpperCase()).join('|');
}

abstract final class TunerPresets {
  static const guitarStandard = TuningPreset(
    name: 'Guitar Standard',
    instrument: InstrumentType.guitar,
    notes: ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
  );
  static const dropD = TuningPreset(
    name: 'Drop D',
    instrument: InstrumentType.guitar,
    notes: ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'],
  );
  static const dStandard = TuningPreset(
    name: 'D Standard',
    instrument: InstrumentType.guitar,
    notes: ['D2', 'G2', 'C3', 'F3', 'A3', 'D4'],
  );
  static const dropC = TuningPreset(
    name: 'Drop C',
    instrument: InstrumentType.guitar,
    notes: ['C2', 'G2', 'C3', 'F3', 'A3', 'D4'],
  );
  static const bassStandard = TuningPreset(
    name: 'Bass Standard',
    instrument: InstrumentType.bass,
    notes: ['E1', 'A1', 'D2', 'G2'],
  );
  static const dadgad = TuningPreset(
    name: 'DADGAD',
    instrument: InstrumentType.guitar,
    notes: ['D2', 'A2', 'D3', 'G3', 'A3', 'D4'],
  );
  static const openG = TuningPreset(
    name: 'Open G',
    instrument: InstrumentType.guitar,
    notes: ['D2', 'G2', 'D3', 'G3', 'B3', 'D4'],
  );
  static const bassDropD = TuningPreset(
    name: 'Bass Drop D',
    instrument: InstrumentType.bass,
    notes: ['D1', 'A1', 'D2', 'G2'],
  );
  static const bassFiveString = TuningPreset(
    name: 'Bass 5-String Standard',
    instrument: InstrumentType.bass,
    notes: ['B0', 'E1', 'A1', 'D2', 'G2'],
  );
  static const all = [
    guitarStandard,
    dropD,
    dStandard,
    dropC,
    dadgad,
    openG,
    bassStandard,
    bassDropD,
    bassFiveString,
  ];
}
