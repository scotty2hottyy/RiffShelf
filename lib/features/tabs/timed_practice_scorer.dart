import 'dart:math' as math;

import '../tuner/pitch_detector.dart';
import 'note_matcher.dart';
import 'practice_timeline.dart';

/// Evaluation state of a single timed note in practice mode.
enum TimedNoteEvaluation {
  /// Note is either not yet evaluated, or is ineligible (e.g. chord,
  /// overlapping note, unknown pitch, technique).
  neutral,

  /// Successfully matched pitch within the timing tolerance window.
  hit,

  /// Passed the timing tolerance window without matching, while microphone
  /// was listening.
  missed,
}

/// Metadata and timing window for an individual note event in timed practice.
class TimedNoteScoringSlot {
  TimedNoteScoringSlot({
    required this.event,
    required this.isEligible,
    this.ineligibleReason,
  });

  final TimedNoteEvent event;
  final bool isEligible;
  final String? ineligibleReason;

  double windowStartBeat = 0;
  double windowEndBeat = 0;
  TimedNoteEvaluation evaluation = TimedNoteEvaluation.neutral;
}

/// Hardware/UI-independent evaluator for hit/miss scoring during timed scrolling practice.
///
/// Keeps tempo-aligned practice scrolling while assessing monophonic single notes.
///
/// **Timing Tolerance Window:**
/// Each eligible single note has a timing window centered around its onset (`startBeat`).
/// The nominal tolerance is ±[timingToleranceSeconds] (default 250 ms), converted to beats
/// using the current BPM: `toleranceBeats = timingToleranceSeconds * (bpm / 60)`.
/// To avoid ambiguity or overlapping windows between adjacent notes, the early tolerance
/// is clamped to at most half the distance to the preceding note onset, and the late
/// tolerance is clamped to at most half the distance to the following note onset.
///
/// **Eligibility:**
/// Only unambiguous single notes with known MIDI pitches within the detector frequency
/// range, without techniques, and not overlapping earlier sounding notes, are scored.
/// Chords, overlapping notes, unknown pitches, techniques, and out-of-range notes remain
/// neutral and are unscored.
///
/// **Sustained Notes:**
/// Reuses [NoteMatcher]'s sustain latching and release gating so held pitches do not
/// falsely match subsequent repeated notes.
///
/// **Microphone Reliability:**
/// When the microphone is not listening (permission denied, no mic, or error),
/// overdue notes remain [TimedNoteEvaluation.neutral] rather than creating false misses.
class TimedPracticeScorer {
  TimedPracticeScorer({
    required this.timeline,
    NoteMatcher? matcher,
    this.supportsPitch,
    this.timingToleranceSeconds = 0.25,
    double bpm = 120,
    double startBeat = 0,
    double? endBeat,
  }) : _matcher = matcher ?? NoteMatcher(),
       _bpm = bpm.clamp(1.0, 1000.0) {
    _classifyNotes();
    _sectionStartBeat = startBeat;
    _sectionEndBeat = endBeat ?? timeline.totalBeats;
    _recalculateWindows();
  }

  final PracticeTimeline timeline;
  final NoteMatcher _matcher;
  final bool Function(int)? supportsPitch;
  final double timingToleranceSeconds;

  double _bpm;
  double get bpm => _bpm;

  double _sectionStartBeat = 0;
  double get sectionStartBeat => _sectionStartBeat;

  double _sectionEndBeat = 0;
  double get sectionEndBeat => _sectionEndBeat;

  double _currentBeat = 0;
  double get currentBeat => _currentBeat;

  bool isMicrophoneActive = false;

  final List<TimedNoteScoringSlot> _allSlots = [];
  final Map<TimedNoteEvent, TimedNoteScoringSlot> _slotByEvent = {};

  int _hits = 0;
  int get hits => _hits;

  int _misses = 0;
  int get misses => _misses;

  int? lastCompletedHits;
  int? lastCompletedMisses;
  double? lastCompletedAccuracy;

  bool _isSectionComplete = false;
  bool get isSectionComplete => _isSectionComplete;

  bool get hasEvaluatedNotes => (_hits + _misses) > 0;

  double get accuracyPercentage {
    final total = _hits + _misses;
    if (total == 0) return 0.0;
    return (_hits / total) * 100.0;
  }

  int get eligibleNoteCount =>
      _sectionSlots.where((slot) => slot.isEligible).length;

  Iterable<TimedNoteScoringSlot> get _sectionSlots => _allSlots.where(
    (slot) =>
        slot.event.startBeat >= _sectionStartBeat &&
        slot.event.startBeat < _sectionEndBeat,
  );

  TimedNoteEvaluation evaluationForNote(TimedNoteEvent event) =>
      _slotByEvent[event]?.evaluation ?? TimedNoteEvaluation.neutral;

  void _classifyNotes() {
    _allSlots.clear();
    _slotByEvent.clear();

    double soundingUntil = 0;
    for (var i = 0; i < timeline.events.length;) {
      final start = timeline.events[i].startBeat;
      final notes = <TimedNoteEvent>[];
      while (i < timeline.events.length &&
          timeline.events[i].startBeat == start) {
        notes.add(timeline.events[i++]);
      }

      final pitch = notes.singleOrNull?.expectedMidiPitch;
      final String? reason;
      if (notes.length > 1) {
        reason = 'chord';
      } else if (start < soundingUntil - 1e-6) {
        reason = 'overlapping';
      } else if (pitch == null || pitch < 0 || pitch > 127) {
        reason = 'missing_pitch';
      } else if (supportsPitch != null && !supportsPitch!(pitch)) {
        reason = 'pitch_out_of_range';
      } else if (notes.single.technique?.trim().isNotEmpty == true) {
        reason = 'technique';
      } else {
        reason = null;
      }

      for (final note in notes) {
        if (note.endBeat > soundingUntil) soundingUntil = note.endBeat;
      }

      for (final note in notes) {
        final slot = TimedNoteScoringSlot(
          event: note,
          isEligible: reason == null,
          ineligibleReason: reason,
        );
        _allSlots.add(slot);
        _slotByEvent[note] = slot;
      }
    }
  }

  void _recalculateWindows() {
    final toleranceBeats = timingToleranceSeconds * (_bpm / 60.0);

    for (var i = 0; i < _allSlots.length; i++) {
      final slot = _allSlots[i];
      if (!slot.isEligible) continue;

      final startBeat = slot.event.startBeat;

      // Find nearest distinct onset before this note
      double? prevOnset;
      for (var p = i - 1; p >= 0; p--) {
        if (_allSlots[p].event.startBeat < startBeat - 1e-6) {
          prevOnset = _allSlots[p].event.startBeat;
          break;
        }
      }

      // Find nearest distinct onset after this note
      double? nextOnset;
      for (var n = i + 1; n < _allSlots.length; n++) {
        if (_allSlots[n].event.startBeat > startBeat + 1e-6) {
          nextOnset = _allSlots[n].event.startBeat;
          break;
        }
      }

      final earlyBound = prevOnset != null
          ? math.max(0.0, (startBeat - prevOnset) / 2.0)
          : toleranceBeats;
      final lateBound = nextOnset != null
          ? math.max(0.0, (nextOnset - startBeat) / 2.0)
          : toleranceBeats;

      final earlyTolerance = math.min(toleranceBeats, earlyBound);
      final lateTolerance = math.min(toleranceBeats, lateBound);

      slot.windowStartBeat = startBeat - earlyTolerance;
      slot.windowEndBeat = startBeat + lateTolerance;
    }
  }

  void setBpm(double bpm) {
    final clamped = bpm.clamp(1.0, 1000.0);
    if ((clamped - _bpm).abs() < 1e-4) return;
    _bpm = clamped;
    _recalculateWindows();
  }

  void setSection({required double startBeat, required double endBeat}) {
    _sectionStartBeat = startBeat;
    _sectionEndBeat = endBeat;
    restart();
  }

  void updatePosition(double currentBeat) {
    _currentBeat = currentBeat;

    if (currentBeat >= _sectionEndBeat) {
      _isSectionComplete = true;
    }

    // Check overdue notes
    for (final slot in _sectionSlots) {
      if (!slot.isEligible) continue;
      if (slot.evaluation != TimedNoteEvaluation.neutral) continue;

      if (currentBeat > slot.windowEndBeat) {
        if (isMicrophoneActive) {
          slot.evaluation = TimedNoteEvaluation.missed;
          _misses++;
        }
        // If microphone was not active, remains neutral to avoid false misses
      }
    }
  }

  void observePitch(PitchResult? pitch) {
    // Locate the active eligible slot in its timing tolerance window
    TimedNoteScoringSlot? candidate;
    for (final slot in _sectionSlots) {
      if (!slot.isEligible) continue;
      if (slot.evaluation != TimedNoteEvaluation.neutral) continue;

      if (_currentBeat >= slot.windowStartBeat &&
          _currentBeat <= slot.windowEndBeat) {
        candidate = slot;
        break;
      }
    }

    if (candidate != null) {
      final result = _matcher.observe(
        expectedMidiPitch: candidate.event.expectedMidiPitch,
        detectedPitch: pitch,
      );

      if (result.status == NoteMatchStatus.matched) {
        candidate.evaluation = TimedNoteEvaluation.hit;
        _hits++;
      }
    } else {
      // Pass null to advance release gating for sustained notes
      _matcher.observe(expectedMidiPitch: null, detectedPitch: pitch);
    }
  }

  void recordLoopWrap(double wrapBeat) {
    lastCompletedHits = _hits;
    lastCompletedMisses = _misses;
    lastCompletedAccuracy = accuracyPercentage;

    _resetSectionEvaluations();
    _hits = 0;
    _misses = 0;
    _isSectionComplete = false;
    _currentBeat = wrapBeat;
    _matcher.reset(preserveSustain: true);
  }

  void seekTo(double targetBeat) {
    if (targetBeat < _currentBeat) {
      // Reset evaluations at or after the seek point
      for (final slot in _sectionSlots) {
        if (!slot.isEligible) continue;
        if (slot.windowEndBeat >= targetBeat) {
          if (slot.evaluation == TimedNoteEvaluation.hit) {
            _hits--;
          } else if (slot.evaluation == TimedNoteEvaluation.missed) {
            _misses--;
          }
          slot.evaluation = TimedNoteEvaluation.neutral;
        }
      }
      _isSectionComplete = false;
    }
    _currentBeat = targetBeat;
    _matcher.reset(preserveSustain: true);
  }

  void restart() {
    _resetSectionEvaluations();
    _hits = 0;
    _misses = 0;
    _isSectionComplete = false;
    _currentBeat = _sectionStartBeat;
    _matcher.reset();
  }

  void resetSession() {
    restart();
    lastCompletedHits = null;
    lastCompletedMisses = null;
    lastCompletedAccuracy = null;
  }

  void _resetSectionEvaluations() {
    for (final slot in _sectionSlots) {
      slot.evaluation = TimedNoteEvaluation.neutral;
    }
  }
}
