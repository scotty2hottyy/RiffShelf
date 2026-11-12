import '../../core/models/instrument_type.dart';
import '../../core/models/saved_tab.dart';
import '../../core/models/tab_structure.dart';
import '../tuner/pitch_detector.dart' show midiFromNoteName;

/// A single note normalized onto the tab's absolute practice timeline, in
/// quarter-note beats measured from the start of the tab. Unlike the raw
/// [TabNote]/[TabBeat] pair it came from, every event here has a positive
/// source duration and a position within its source measure.
class TimedNoteEvent {
  const TimedNoteEvent({
    required this.startBeat,
    required this.durationBeats,
    required this.stringNumber,
    required this.fret,
    required this.measureNumber,
    this.technique,
    this.expectedMidiPitch,
  });

  final double startBeat;
  final double durationBeats;
  final int stringNumber;
  final int fret;
  final int measureNumber;
  final String? technique;

  /// Source MIDI pitch, or an unambiguous tuning/fret fallback. Null does not
  /// affect ordinary timed practice. Source pitch is never capo-adjusted here.
  final int? expectedMidiPitch;

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
/// can be messy. Invalid timing makes the entire timeline unsuitable for
/// playback; callers can then display static tablature instead of guessing.
class PracticeTimeline {
  factory PracticeTimeline.fromTab(SavedTab tab) {
    final markers = <MeasureMarker>[];
    final events = <TimedNoteEvent>[];
    // Keyed by string + rounded onset beat so exact duplicate note events
    // collapse to one (keeping the last write), while chords - distinct
    // strings sounding at the same beat - are left untouched.
    final indexByKey = <String, int>{};
    var hasReliableTiming =
        tab.tabType != TabType.other &&
        tab.tabType != TabType.chords &&
        tab.tuning.length == tab.stringCount;

    var cursor = 0.0;
    for (final measure in tab.measures) {
      final measureLength = _measureLengthBeats(measure);
      if (measureLength == null) {
        hasReliableTiming = false;
        break;
      }
      markers.add(MeasureMarker(number: measure.number, startBeat: cursor));

      // Beats aren't guaranteed to arrive in time order from every source,
      // so normalize on a time-sorted copy.
      final orderedBeats = [...measure.beats]
        ..sort((a, b) => a.position.compareTo(b.position));

      for (final beat in orderedBeats) {
        if (!beat.position.isFinite ||
            beat.position < 0 ||
            beat.position >= measureLength ||
            !beat.duration.isFinite ||
            beat.duration <= 0) {
          hasReliableTiming = false;
          continue;
        }
        if (beat.isRest || beat.notes.isEmpty) continue;
        final onset = _round(cursor + beat.position);
        for (final note in beat.notes) {
          final rawDuration = note.duration ?? beat.duration;
          if (note.stringNumber < 1 ||
              note.stringNumber > tab.stringCount ||
              note.fret < 0 ||
              !rawDuration.isFinite ||
              rawDuration <= 0) {
            hasReliableTiming = false;
            continue;
          }
          final duration = _round(rawDuration);
          final key = '${note.stringNumber}:$onset';
          final event = TimedNoteEvent(
            startBeat: onset,
            durationBeats: duration,
            stringNumber: note.stringNumber,
            fret: note.fret,
            measureNumber: measure.number,
            technique: note.technique,
            expectedMidiPitch: _expectedPitch(tab, note),
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
      events: hasReliableTiming ? List.unmodifiable(events) : const [],
      measures: hasReliableTiming ? List.unmodifiable(markers) : const [],
      totalBeats: hasReliableTiming ? cursor : 0,
      hasReliableTiming: hasReliableTiming && events.isNotEmpty,
    );
  }

  const PracticeTimeline._({
    required this.events,
    required this.measures,
    required this.totalBeats,
    required this.hasReliableTiming,
  });

  /// Time-ordered, normalized note events.
  final List<TimedNoteEvent> events;

  /// Measure boundaries, in the same order as the source tab's measures.
  final List<MeasureMarker> measures;

  /// Length of the full tab, in quarter-note beats.
  final double totalBeats;

  /// Whether the source can safely drive timed playback.
  final bool hasReliableTiming;

  static int? _expectedPitch(SavedTab tab, TabNote note) {
    if (note.midiPitch != null) return note.midiPitch;
    // Importers retain capo separately, and the model does not say whether
    // tuning is already transposed. Do not guess a missing pitch with a capo.
    if (tab.capo != 0 || tab.tuning.length != tab.stringCount) return null;
    // Tuning is low-to-high; tablature string 1 is the highest string.
    final openPitch = midiFromNoteName(
      tab.tuning[tab.stringCount - note.stringNumber],
    );
    if (openPitch == null || openPitch < 0 || openPitch > 127) return null;
    final pitch = openPitch + note.fret;
    return pitch >= 0 && pitch <= 127 ? pitch : null;
  }

  static double? _measureLengthBeats(TabMeasure measure) {
    if (measure.numerator <= 0 || measure.denominator <= 0) return null;
    final length = measure.numerator * 4 / measure.denominator;
    return length.isFinite && length > 0 ? length : null;
  }

  /// Rounds to a tenth of a millibeat to absorb binary floating-point drift
  /// from repeated measure-length accumulation without affecting musically
  /// meaningful timing.
  static double _round(double value) => (value * 1e6).round() / 1e6;
}
