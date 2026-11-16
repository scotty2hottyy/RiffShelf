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

/// Human-friendly names for widely used guitar/bass tunings, used to keep
/// compact UI surfaces (such as Library cards) from showing a raw list of
/// string pitches. Matching is by pitch class only, so it recognizes a
/// tuning regardless of octave digits (e.g. "E2") or enharmonic spelling
/// (e.g. "Eb" vs "D#").
abstract final class CommonTuningNames {
  /// Shown when no recognized preset matches the saved tuning notes.
  static const fallback = 'Custom Tuning';

  static const _guitarPresets = {
    'Standard': ['E', 'A', 'D', 'G', 'B', 'E'],
    'Drop D': ['D', 'A', 'D', 'G', 'B', 'E'],
    'Half-Step Down': ['D#', 'G#', 'C#', 'F#', 'A#', 'D#'],
    'D Standard': ['D', 'G', 'C', 'F', 'A', 'D'],
    'Drop C': ['C', 'G', 'C', 'F', 'A', 'D'],
    'DADGAD': ['D', 'A', 'D', 'G', 'A', 'D'],
    'Open G': ['D', 'G', 'D', 'G', 'B', 'D'],
  };
  static const _bassPresets = {
    'Standard': ['E', 'A', 'D', 'G'],
    'Drop D': ['D', 'A', 'D', 'G'],
    'Half-Step Down': ['D#', 'G#', 'C#', 'F#'],
    'D Standard': ['D', 'G', 'C', 'F'],
  };

  static const _pitchClasses = {
    'C': 0,
    'B#': 0,
    'C#': 1,
    'DB': 1,
    'D': 2,
    'D#': 3,
    'EB': 3,
    'E': 4,
    'FB': 4,
    'F': 5,
    'E#': 5,
    'F#': 6,
    'GB': 6,
    'G': 7,
    'G#': 8,
    'AB': 8,
    'A': 9,
    'A#': 10,
    'BB': 10,
    'B': 11,
    'CB': 11,
  };
  static final _notePattern = RegExp(r'^([A-Ga-g])([#Bb])?');

  static int? _pitchClass(String note) {
    final match = _notePattern.firstMatch(note.trim());
    if (match == null) return null;
    final letter = match.group(1)!.toUpperCase();
    final accidental = match.group(2)?.toUpperCase();
    return _pitchClasses[accidental == null ? letter : '$letter$accidental'];
  }

  static List<int>? _signature(List<String> notes) {
    final classes = <int>[];
    for (final note in notes) {
      final value = _pitchClass(note);
      if (value == null) return null;
      classes.add(value);
    }
    return classes;
  }

  /// Returns the common name for [notes] (low to high), checked against the
  /// presets for [instrument]. Unknown placeholders (e.g. "?") or a tuning
  /// that does not match a recognized preset return [fallback].
  static String of(List<String> notes, InstrumentType instrument) {
    final signature = _signature(notes);
    if (signature == null) return fallback;
    final presetSets = switch (instrument) {
      InstrumentType.guitar => [_guitarPresets],
      InstrumentType.bass => [_bassPresets],
      InstrumentType.other => [_guitarPresets, _bassPresets],
    };
    for (final presets in presetSets) {
      for (final entry in presets.entries) {
        if (listEquals(signature, _signature(entry.value))) return entry.key;
      }
    }
    return fallback;
  }
}
