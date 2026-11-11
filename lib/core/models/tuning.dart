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
