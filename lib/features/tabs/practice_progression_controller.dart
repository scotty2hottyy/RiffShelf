import '../tuner/pitch_detector.dart' show PitchResult;
import 'note_matcher.dart';
import 'practice_timeline.dart';

enum UnsupportedPassageReason {
  chord,
  overlappingNotes,
  missingPitch,
  outsidePitchRange,
  technique,
}

class SkippedPracticePassage {
  const SkippedPracticePassage({required this.notes, required this.reason});
  final List<TimedNoteEvent> notes;
  final UnsupportedPassageReason reason;
  double get startBeat => notes.first.startBeat;
}

class PracticeProgressionResult {
  const PracticeProgressionResult({
    required this.positionBeats,
    required this.completed,
    this.match,
    this.matchedEvent,
    this.looped = false,
  });
  final double positionBeats;
  final bool completed;
  final NoteMatchResult? match;
  final TimedNoteEvent? matchedEvent;
  final bool looped;
}

/// Hardware/widget-independent, monophonic "wait for the note" progression.
///
/// Position jumps across rests/gaps and unsupported passages to the next
/// supported onset; it is not a clock and does not assess rhythm or held duration.
/// Skipped passages are never credited as matched. Seeking inside a note chooses
/// the next onset, rather than asking for a retroactive attack.
class PracticeProgressionController {
  PracticeProgressionController(
    this.timeline, {
    NoteMatcher? matcher,
    bool Function(int)? supportsPitch,
    bool looping = false,
    bool allowApproximateTiming = false,
  }) : _matcher = matcher ?? NoteMatcher() {
    _looping = looping;
    if (timeline.hasReliableTiming || allowApproximateTiming) {
      _classify(supportsPitch);
    }
    _sectionEnd = timeline.totalBeats;
    restart();
  }

  final PracticeTimeline timeline;
  final NoteMatcher _matcher;
  final List<TimedNoteEvent> _supported = [];
  final List<SkippedPracticePassage> _skipped = [];
  List<TimedNoteEvent> _sectionEvents = [];
  double _sectionStart = 0;
  double _sectionEnd = 0;
  double _position = 0;
  int _index = 0;
  int _loopCount = 0;
  late bool _looping;

  double get positionBeats => _position;
  double get sectionStartBeat => _sectionStart;
  double get sectionEndBeat => _sectionEnd;
  int get loopCount => _loopCount;
  bool get looping => _looping;
  bool get completed => _index >= _sectionEvents.length;
  TimedNoteEvent? get expectedEvent =>
      completed ? null : _sectionEvents[_index];
  List<SkippedPracticePassage> get skippedPassages => List.unmodifiable(
    _skipped.where(
      (passage) =>
          passage.startBeat >= _sectionStart && passage.startBeat < _sectionEnd,
    ),
  );

  void _classify(bool Function(int)? supportsPitch) {
    double soundingUntil = 0;
    for (var i = 0; i < timeline.events.length;) {
      final start = timeline.events[i].startBeat;
      final notes = <TimedNoteEvent>[];
      while (i < timeline.events.length &&
          timeline.events[i].startBeat == start) {
        notes.add(timeline.events[i++]);
      }
      final pitch = notes.singleOrNull?.expectedMidiPitch;
      final UnsupportedPassageReason? reason;
      if (notes.length > 1) {
        // Even a unison on two strings is not evidence of both strings played.
        reason = UnsupportedPassageReason.chord;
      } else if (start < soundingUntil - 1e-6) {
        reason = UnsupportedPassageReason.overlappingNotes;
      } else if (pitch == null || pitch < 0 || pitch > 127) {
        reason = UnsupportedPassageReason.missingPitch;
      } else if (supportsPitch != null && !supportsPitch(pitch)) {
        reason = UnsupportedPassageReason.outsidePitchRange;
      } else if (notes.single.technique?.trim().isNotEmpty == true) {
        reason = UnsupportedPassageReason.technique;
      } else {
        reason = null;
      }
      for (final note in notes) {
        if (note.endBeat > soundingUntil) soundingUntil = note.endBeat;
      }
      if (reason == null) {
        _supported.add(notes.single);
      } else {
        _skipped.add(
          SkippedPracticePassage(
            notes: List.unmodifiable(notes),
            reason: reason,
          ),
        );
      }
    }
  }

  /// Discard pre-pause observations while still requiring a repeated note to
  /// be released before it can match again.
  void clearEvidence() => _matcher.reset(preserveSustain: true);

  void setLooping(bool enabled) => _looping = enabled;

  /// Half-open beat range [startBeat, endBeat). Resets the current attempt.
  /// An empty range or a range with only unsupported notes finishes immediately.
  void setSection({required double startBeat, required double endBeat}) {
    if (!startBeat.isFinite ||
        !endBeat.isFinite ||
        startBeat < 0 ||
        endBeat < startBeat ||
        endBeat > timeline.totalBeats) {
      throw ArgumentError(
        'Section must be a finite range inside the timeline.',
      );
    }
    _sectionStart = startBeat;
    _sectionEnd = endBeat;
    restart();
  }

  void restart() {
    _sectionEvents = _supported
        .where(
          (event) =>
              event.startBeat >= _sectionStart && event.startBeat < _sectionEnd,
        )
        .toList();
    _loopCount = 0;
    seek(_sectionStart);
  }

  /// An intentional reposition starts fresh, including the sustain latch.
  void seek(double beat) {
    if (!beat.isFinite) {
      throw ArgumentError.value(beat, 'beat', 'Must be finite.');
    }
    final target = beat.clamp(_sectionStart, _sectionEnd);
    _matcher.reset();
    _index = _sectionEvents.indexWhere((event) => event.startBeat >= target);
    if (_index < 0) _index = _sectionEvents.length;
    _position = expectedEvent?.startBeat ?? _sectionEnd;
  }

  /// Consume a new detector observation once. Never reuse one frame to confirm
  /// multiple notes, even when it completes a section and wraps a loop.
  PracticeProgressionResult observe(PitchResult? detection) {
    final expected = expectedEvent;
    if (expected == null) {
      return PracticeProgressionResult(
        positionBeats: _position,
        completed: true,
      );
    }
    final result = _matcher.observe(
      expectedMidiPitch: expected.expectedMidiPitch,
      detectedPitch: detection,
    );
    if (result.status != NoteMatchStatus.matched) {
      return PracticeProgressionResult(
        positionBeats: _position,
        completed: false,
        match: result,
      );
    }
    _index++;
    var looped = false;
    if (completed && _looping) {
      _index = 0;
      _loopCount++;
      looped = true;
    }
    // Preserve the last confirmed pitch across repeated notes and loop wraps.
    _matcher.reset(preserveSustain: true);
    _position = expectedEvent?.startBeat ?? _sectionEnd;
    return PracticeProgressionResult(
      positionBeats: _position,
      completed: completed,
      match: result,
      matchedEvent: expected,
      looped: looped,
    );
  }
}
