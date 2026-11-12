import '../tuner/pitch_detector.dart';

enum NoteMatchStatus { matched, notMatched, insufficientEvidence }

class NoteMatchResult {
  const NoteMatchResult(
    this.status, {
    this.centsDifference,
    this.matchingObservations = 0,
  });

  final NoteMatchStatus status;
  final double? centsDifference;
  final int matchingObservations;
}

/// Stateful, monophonic matching of distinct detector observations, not audio.
///
/// Match against the exact MIDI octave. A confirmed pitch stays latched until
/// [releaseObservations] consecutive no-pitch observations or confident pitches
/// at least a semitone away. Invalid/low-confidence data cannot release it.
/// This is conservative release gating, not pluck/onset recognition.
class NoteMatcher {
  // Cents conversion can round infinitesimally past an inclusive boundary.
  static const _roundingEpsilon = 1e-9;

  NoteMatcher({
    this.toleranceCents = 25,
    this.minimumConfidence = 0.85,
    this.requiredObservations = 3,
    this.stabilityCents = 15,
    this.releaseObservations = 2,
  }) {
    if (!toleranceCents.isFinite ||
        toleranceCents <= 0 ||
        toleranceCents > 50) {
      throw ArgumentError.value(
        toleranceCents,
        'toleranceCents',
        'Must be in (0, 50].',
      );
    }
    if (!minimumConfidence.isFinite ||
        minimumConfidence <= 0 ||
        minimumConfidence > 1) {
      throw ArgumentError.value(
        minimumConfidence,
        'minimumConfidence',
        'Must be in (0, 1].',
      );
    }
    if (requiredObservations < 2) {
      throw ArgumentError.value(
        requiredObservations,
        'requiredObservations',
        'Must be at least two.',
      );
    }
    if (!stabilityCents.isFinite ||
        stabilityCents <= 0 ||
        stabilityCents > 100) {
      throw ArgumentError.value(
        stabilityCents,
        'stabilityCents',
        'Must be in (0, 100].',
      );
    }
    if (releaseObservations < 2) {
      throw ArgumentError.value(
        releaseObservations,
        'releaseObservations',
        'Must be at least two.',
      );
    }
  }

  final double toleranceCents;
  final double minimumConfidence;
  final int requiredObservations;
  final double stabilityCents;
  final int releaseObservations;
  int? _expectedPitch;
  int? _latchedPitch;
  int _releaseCount = 0;
  int _matches = 0;
  double? _lowestCents;
  double? _highestCents;

  /// Restart matching, including release gating. Do not call this simply to
  /// request the next repeated note: sustained-note protection must survive it.
  void reset() {
    _expectedPitch = null;
    _latchedPitch = null;
    _releaseCount = 0;
    _clearEvidence();
  }

  void _clearEvidence() {
    _matches = 0;
    _lowestCents = null;
    _highestCents = null;
  }

  /// Supply one new detector frame per call; null means no detected pitch.
  /// Expected-pitch changes clear evidence but preserve sustained-note gating.
  /// Unknown or invalid expected MIDI pitches cannot be confirmed.
  NoteMatchResult observe({
    required int? expectedMidiPitch,
    required PitchResult? detectedPitch,
  }) {
    if (_expectedPitch != expectedMidiPitch) {
      _expectedPitch = expectedMidiPitch;
      _clearEvidence();
    }
    final validDetection =
        detectedPitch != null &&
        detectedPitch.frequency.isFinite &&
        detectedPitch.frequency > 0 &&
        detectedPitch.confidence.isFinite &&
        detectedPitch.confidence >= minimumConfidence &&
        detectedPitch.confidence <= 1;

    if (_latchedPitch != null) {
      final released =
          detectedPitch == null ||
          (validDetection &&
              centsBetween(
                    detectedPitch.frequency,
                    frequencyFromMidi(_latchedPitch!),
                  ).abs() >=
                  100 - _roundingEpsilon);
      _releaseCount = released ? _releaseCount + 1 : 0;
      if (_releaseCount >= releaseObservations) {
        _latchedPitch = null;
        _releaseCount = 0;
      }
    }

    if (!validDetection ||
        expectedMidiPitch == null ||
        expectedMidiPitch < 0 ||
        expectedMidiPitch > 127) {
      _clearEvidence();
      return const NoteMatchResult(NoteMatchStatus.insufficientEvidence);
    }
    final cents = centsBetween(
      detectedPitch.frequency,
      frequencyFromMidi(expectedMidiPitch),
    );
    if (!cents.isFinite || cents.abs() > toleranceCents + _roundingEpsilon) {
      _clearEvidence();
      return NoteMatchResult(
        NoteMatchStatus.notMatched,
        centsDifference: cents,
      );
    }
    if (_latchedPitch == expectedMidiPitch) {
      _clearEvidence();
      return NoteMatchResult(
        NoteMatchStatus.insufficientEvidence,
        centsDifference: cents,
      );
    }

    final low = _lowestCents == null || cents < _lowestCents!
        ? cents
        : _lowestCents!;
    final high = _highestCents == null || cents > _highestCents!
        ? cents
        : _highestCents!;
    if (high - low > stabilityCents + _roundingEpsilon) {
      _clearEvidence();
    }
    _lowestCents = _lowestCents == null || cents < _lowestCents!
        ? cents
        : _lowestCents;
    _highestCents = _highestCents == null || cents > _highestCents!
        ? cents
        : _highestCents;
    _matches++;
    if (_matches < requiredObservations) {
      return NoteMatchResult(
        NoteMatchStatus.insufficientEvidence,
        centsDifference: cents,
        matchingObservations: _matches,
      );
    }
    final count = _matches;
    _latchedPitch = expectedMidiPitch;
    _releaseCount = 0;
    _clearEvidence();
    return NoteMatchResult(
      NoteMatchStatus.matched,
      centsDifference: cents,
      matchingObservations: count,
    );
  }
}
