import 'package:flutter/foundation.dart';

import 'instrument_type.dart';

/// Instruments selectable in the tuner feature.
///
/// Kept separate from [InstrumentType] (used by the tab library, search, and
/// import features) so that adding wind instruments to the tuner does not
/// affect those unrelated screens.
enum TunerInstrument {
  guitar,
  bass,
  saxophone,
  clarinet,
  flute,
  trumpet,
  frenchHorn;

  String get label => switch (this) {
    guitar => 'Guitar',
    bass => 'Bass',
    saxophone => 'Saxophone',
    clarinet => 'Clarinet',
    flute => 'Flute',
    trumpet => 'Trumpet',
    frenchHorn => 'French Horn',
  };

  /// Guitar and bass tune several strings individually; the other
  /// instruments tune a single reference pitch (concert A440).
  bool get hasStrings => this == guitar || this == bass;

  static TunerInstrument fromJson(String value) => TunerInstrument.values
      .firstWhere((type) => type.name == value, orElse: () => guitar);

  /// Maps a saved tab's library instrument onto the tuner's instrument set;
  /// the tab library only stores guitar/bass tunings today.
  static TunerInstrument fromTabInstrument(InstrumentType type) =>
      type == InstrumentType.bass ? bass : guitar;
}

@immutable
class TuningPreset {
  const TuningPreset({
    required this.name,
    required this.instrument,
    required this.notes,
  });
  final String name;
  final TunerInstrument instrument;
  final List<String> notes;
  int get stringCount => notes.length;
}

abstract final class StandardTunings {
  static const guitarStandard = TuningPreset(
    name: 'Standard',
    instrument: TunerInstrument.guitar,
    notes: ['E', 'A', 'D', 'G', 'B', 'E'],
  );
  static const bassStandard = TuningPreset(
    name: 'Standard',
    instrument: TunerInstrument.bass,
    notes: ['E', 'A', 'D', 'G'],
  );
  static const guitarDropD = TuningPreset(
    name: 'Drop D',
    instrument: TunerInstrument.guitar,
    notes: ['D', 'A', 'D', 'G', 'B', 'E'],
  );
  static const all = [guitarStandard, bassStandard, guitarDropD];

  static TuningPreset? infer(
    List<String> notes, {
    TunerInstrument? instrument,
  }) {
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
    instrument: TunerInstrument.guitar,
    notes: ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
  );
  static const dropD = TuningPreset(
    name: 'Drop D',
    instrument: TunerInstrument.guitar,
    notes: ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'],
  );
  static const dStandard = TuningPreset(
    name: 'D Standard',
    instrument: TunerInstrument.guitar,
    notes: ['D2', 'G2', 'C3', 'F3', 'A3', 'D4'],
  );
  static const dropC = TuningPreset(
    name: 'Drop C',
    instrument: TunerInstrument.guitar,
    notes: ['C2', 'G2', 'C3', 'F3', 'A3', 'D4'],
  );
  static const bassStandard = TuningPreset(
    name: 'Bass Standard',
    instrument: TunerInstrument.bass,
    notes: ['E1', 'A1', 'D2', 'G2'],
  );
  static const dadgad = TuningPreset(
    name: 'DADGAD',
    instrument: TunerInstrument.guitar,
    notes: ['D2', 'A2', 'D3', 'G3', 'A3', 'D4'],
  );
  static const openG = TuningPreset(
    name: 'Open G',
    instrument: TunerInstrument.guitar,
    notes: ['D2', 'G2', 'D3', 'G3', 'B3', 'D4'],
  );
  static const bassDropD = TuningPreset(
    name: 'Bass Drop D',
    instrument: TunerInstrument.bass,
    notes: ['D1', 'A1', 'D2', 'G2'],
  );
  static const bassFiveString = TuningPreset(
    name: 'Bass 5-String Standard',
    instrument: TunerInstrument.bass,
    notes: ['B0', 'E1', 'A1', 'D2', 'G2'],
  );

  /// Wind instruments tune a single reference pitch rather than several
  /// strings; concert A440 is the standard reference pitch used by bands and
  /// orchestras for saxophone, clarinet, flute, trumpet, and French horn.
  static const saxophoneStandard = TuningPreset(
    name: 'Saxophone Standard',
    instrument: TunerInstrument.saxophone,
    notes: ['A4'],
  );
  static const clarinetStandard = TuningPreset(
    name: 'Clarinet Standard',
    instrument: TunerInstrument.clarinet,
    notes: ['A4'],
  );
  static const fluteStandard = TuningPreset(
    name: 'Flute Standard',
    instrument: TunerInstrument.flute,
    notes: ['A4'],
  );
  static const trumpetStandard = TuningPreset(
    name: 'Trumpet Standard',
    instrument: TunerInstrument.trumpet,
    notes: ['A4'],
  );
  static const frenchHornStandard = TuningPreset(
    name: 'French Horn Standard',
    instrument: TunerInstrument.frenchHorn,
    notes: ['A4'],
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
    saxophoneStandard,
    clarinetStandard,
    fluteStandard,
    trumpetStandard,
    frenchHornStandard,
  ];
}
