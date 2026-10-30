import 'package:flutter/foundation.dart';

@immutable
class TabNote {
  const TabNote({
    required this.stringNumber,
    required this.fret,
    this.midiPitch,
    this.duration,
    this.technique,
  }) : assert(stringNumber > 0),
       assert(fret >= 0);
  final int stringNumber;
  final int fret;
  final int? midiPitch;

  /// Duration in quarter-note beats.
  final double? duration;
  final String? technique;

  Map<String, Object?> toJson() => {
    'stringNumber': stringNumber,
    'fret': fret,
    'midiPitch': midiPitch,
    'duration': duration,
    'technique': technique,
  };

  factory TabNote.fromJson(Map<String, Object?> json) => TabNote(
    stringNumber: json['stringNumber']! as int,
    fret: json['fret']! as int,
    midiPitch: json['midiPitch'] as int?,
    duration: (json['duration'] as num?)?.toDouble(),
    technique: json['technique'] as String?,
  );
}

@immutable
class TabBeat {
  const TabBeat({
    required this.position,
    this.duration = 1,
    this.notes = const [],
    this.isRest = false,
  });

  /// Position within the measure in quarter-note beats.
  final double position;

  /// Duration in quarter-note beats.
  final double duration;
  final List<TabNote> notes;
  final bool isRest;

  Map<String, Object?> toJson() => {
    'position': position,
    'duration': duration,
    'isRest': isRest,
    'notes': notes.map((note) => note.toJson()).toList(),
  };

  factory TabBeat.fromJson(Map<String, Object?> json) => TabBeat(
    position: (json['position']! as num).toDouble(),
    duration: (json['duration'] as num?)?.toDouble() ?? 1,
    isRest: json['isRest'] as bool? ?? false,
    notes: (json['notes']! as List<Object?>)
        .map((note) => TabNote.fromJson(note! as Map<String, Object?>))
        .toList(),
  );
}

@immutable
class TabMeasure {
  const TabMeasure({
    required this.number,
    this.numerator = 4,
    this.denominator = 4,
    this.beats = const [],
  });
  final int number;
  final int numerator;
  final int denominator;
  final List<TabBeat> beats;

  Map<String, Object?> toJson() => {
    'number': number,
    'numerator': numerator,
    'denominator': denominator,
    'beats': beats.map((beat) => beat.toJson()).toList(),
  };

  factory TabMeasure.fromJson(Map<String, Object?> json) => TabMeasure(
    number: json['number']! as int,
    numerator: json['numerator']! as int,
    denominator: json['denominator']! as int,
    beats: (json['beats']! as List<Object?>)
        .map((beat) => TabBeat.fromJson(beat! as Map<String, Object?>))
        .toList(),
  );
}
