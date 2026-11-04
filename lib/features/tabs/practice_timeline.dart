import '../../core/models/saved_tab.dart';
import '../../core/models/tab_structure.dart';

/// Smallest duration (in quarter-note beats) assigned to a note so it always
/// renders with a visible, non-zero span even when source data is missing,
/// zero, or negative.
const double minNoteDurationBeats = 0.05;

/// A single note normalized onto the tab's absolute practice timeline, in
/// quarter-note beats measured from the start of the tab. Unlike the raw
/// [TabNote]/[TabBeat] pair it came from, every event here has a guaranteed
/// positive duration and a position clamped to its source measure.
class TimedNoteEvent {
  const TimedNoteEvent({
    required this.startBeat,
    required this.durationBeats,
    required this.stringNumber,
    required this.fret,
    required this.measureNumber,
    this.technique,
  });

  final double startBeat;
  final double durationBeats;
  final int stringNumber;
  final int fret;
  final int measureNumber;
  final String? technique;

  double get endBeat => startBeat + durationBeats;
}

/// A measure boundary on the same absolute timeline as [TimedNoteEvent].
class MeasureMarker {
  const MeasureMarker({required this.number, required this.startBeat});
  final int number;
  final double startBeat;
}

/// Normalizes a [SavedTab]'s raw measure/beat/note structure into a flat,
/// chronologically-sorted list of [TimedNoteEvent]s that practice playback
/// can scrub through deterministically, independent of any particular tempo.
///
/// Source tab data (hand-edited, imported, or parsed from ASCII/Guitar Pro)
/// can be messy: beats may arrive out of time order within a measure, carry
/// a missing/zero/negative duration, declare a position outside the
/// measure's bounds, use an invalid time signature, or duplicate the exact
/// same note twice. This collapses all of that into clean, clamped,
/// de-duplicated, time-ordered events so the practice scroller never has to
/// special-case malformed input.
class PracticeTimeline {
  factory PracticeTimeline.fromTab(SavedTab tab) {
    final markers = <MeasureMarker>[];
    final events = <TimedNoteEvent>[];
    // Keyed by string + rounded onset beat so exact duplicate note events
    // collapse to one (keeping the last write), while chords - distinct
    // strings sounding at the same beat - are left untouched.
    final indexByKey = <String, int>{};

    var cursor = 0.0;
    for (final measure in tab.measures) {
      final measureLength = _measureLengthBeats(measure);
      markers.add(MeasureMarker(number: measure.number, startBeat: cursor));

      // Beats aren't guaranteed to arrive in time order from every source,
      // so normalize on a time-sorted copy.
      final orderedBeats = [...measure.beats]
        ..sort((a, b) => a.position.compareTo(b.position));

      for (final beat in orderedBeats) {
        if (beat.isRest || beat.notes.isEmpty) continue;
        final position = beat.position.clamp(0, measureLength).toDouble();
        final onset = _round(cursor + position);
        for (final note in beat.notes) {
          final rawDuration = note.duration ?? beat.duration;
          final duration = _round(
            rawDuration <= 0 ? minNoteDurationBeats : rawDuration,
          );
          final key = '${note.stringNumber}:$onset';
          final event = TimedNoteEvent(
            startBeat: onset,
            durationBeats: duration,
            stringNumber: note.stringNumber,
            fret: note.fret,
            measureNumber: measure.number,
            technique: note.technique,
          );
          final existingIndex = indexByKey[key];
          if (existingIndex != null) {
            events[existingIndex] = event;
          } else {
            indexByKey[key] = events.length;
            events.add(event);
          }
        }
      }
      cursor = _round(cursor + measureLength);
    }

    events.sort((a, b) {
      final byBeat = a.startBeat.compareTo(b.startBeat);
      return byBeat != 0 ? byBeat : a.stringNumber.compareTo(b.stringNumber);
    });

    return PracticeTimeline._(
      events: List.unmodifiable(events),
      measures: List.unmodifiable(markers),
      totalBeats: cursor,
    );
  }

  const PracticeTimeline._({
    required this.events,
    required this.measures,
    required this.totalBeats,
  });

  /// Time-ordered, normalized note events.
  final List<TimedNoteEvent> events;

  /// Measure boundaries, in the same order as the source tab's measures.
  final List<MeasureMarker> measures;

  /// Length of the full tab, in quarter-note beats.
  final double totalBeats;

  static double _measureLengthBeats(TabMeasure measure) {
    final numerator = measure.numerator > 0 ? measure.numerator : 4;
    final denominator = measure.denominator > 0 ? measure.denominator : 4;
    return numerator * 4 / denominator;
  }

  /// Rounds to a tenth of a millibeat to absorb binary floating-point drift
  /// from repeated measure-length accumulation without affecting musically
  /// meaningful timing.
  static double _round(double value) => (value * 1e6).round() / 1e6;
}
