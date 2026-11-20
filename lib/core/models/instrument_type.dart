/// Instrument a tab is written for.
enum InstrumentType {
  guitar,
  bass,
  other;

  String get label => switch (this) {
    guitar => 'Guitar',
    bass => 'Bass',
    other => 'Other',
  };

  /// Parses a stored name; unknown values become [other].
  static InstrumentType fromJson(String value) => InstrumentType.values
      .firstWhere((type) => type.name == value, orElse: () => other);
}

/// Kind of tablature, used for filtering and display.
enum TabType {
  tab,
  bass,
  chords,
  guitarPro,
  other;

  String get label => switch (this) {
    tab => 'Guitar',
    bass => 'Bass',
    chords => 'Chords',
    guitarPro => 'Guitar Pro',
    other => 'Other',
  };

  static TabType fromValue(String? value) {
    final normalized = value?.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return switch (normalized) {
      'tab' || 'tabs' || 'guitar' => tab,
      'bass' || 'basstab' => bass,
      'chord' || 'chords' => chords,
      'guitarpro' || 'pro' => guitarPro,
      _ => other,
    };
  }
}

/// Construction of the instrument, independent of guitar or bass.
enum InstrumentClassification {
  acoustic,
  electric,
  other;

  String get label => switch (this) {
    acoustic => 'Acoustic',
    electric => 'Electric',
    other => 'Other',
  };
}
