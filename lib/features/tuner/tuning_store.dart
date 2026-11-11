import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/tuning.dart';
import 'pitch_detector.dart';

/// The microphone detector supports approximately A0 through B5.
String? tuningValidationError(
  String name,
  TunerInstrument instrument,
  List<String> notes,
) {
  if (name.trim().isEmpty || name.trim().length > 40) {
    return 'Enter a name of 1–40 characters.';
  }
  final validCount = switch (instrument) {
    TunerInstrument.guitar => notes.length >= 6 && notes.length <= 12,
    TunerInstrument.bass => notes.length >= 4 && notes.length <= 6,
    _ => notes.length == 1,
  };
  if (!validCount) {
    return instrument.hasStrings
        ? 'Use 6–12 guitar strings or 4–6 bass strings.'
        : 'Enter a single reference note.';
  }
  for (final note in notes) {
    final normalized = note.trim();
    final midi = midiFromNoteName(normalized);
    if (midi == null || midi < 21 || midi > 83) {
      return 'Use notes from A0 through B5, such as E2 or F#3.';
    }
  }
  return null;
}

class CustomTuning {
  const CustomTuning({required this.id, required this.preset});

  final String id;
  final TuningPreset preset;

  Map<String, Object> toJson() => {
    'id': id,
    'name': preset.name,
    'instrument': preset.instrument.name,
    'notes': preset.notes,
  };

  static CustomTuning? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final name = value['name'];
    final instrumentName = value['instrument'];
    final rawNotes = value['notes'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        instrumentName is! String ||
        rawNotes is! List ||
        !rawNotes.every((note) => note is String)) {
      return null;
    }
    final instrument = TunerInstrument.fromJson(instrumentName);
    // Custom tunings are only supported for stringed instruments.
    if (!instrument.hasStrings) return null;
    final notes = rawNotes.cast<String>();
    if (tuningValidationError(name, instrument, notes) != null) return null;
    return CustomTuning(
      id: id,
      preset: TuningPreset(
        name: name.trim(),
        instrument: instrument,
        notes: List.unmodifiable(notes.map((note) => note.trim())),
      ),
    );
  }
}

class TunerSettings {
  const TunerSettings({this.customTunings = const [], this.selectedId});

  final List<CustomTuning> customTunings;
  final String? selectedId;

  Map<String, Object?> toJson() => {
    'customTunings': customTunings.map((item) => item.toJson()).toList(),
    'selectedId': selectedId,
  };

  static TunerSettings fromJson(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return const TunerSettings();
      final items = value['customTunings'];
      return TunerSettings(
        customTunings: items is List
            ? List.unmodifiable(
                items.map(CustomTuning.fromJson).whereType<CustomTuning>(),
              )
            : const [],
        selectedId: value['selectedId'] is String
            ? value['selectedId'] as String
            : null,
      );
    } catch (_) {
      return const TunerSettings();
    }
  }
}

abstract interface class TunerSettingsStore {
  Future<TunerSettings> load();
  Future<void> save(TunerSettings settings);
}

class LocalTunerSettingsStore implements TunerSettingsStore {
  LocalTunerSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const key = 'tuner.settings.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<TunerSettings> load() async {
    final raw = await _preferences.getString(key);
    return raw == null ? const TunerSettings() : TunerSettings.fromJson(raw);
  }

  @override
  Future<void> save(TunerSettings settings) =>
      _preferences.setString(key, jsonEncode(settings.toJson()));
}
