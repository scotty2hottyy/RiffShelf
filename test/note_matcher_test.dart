import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/features/tabs/note_matcher.dart';
import 'package:riffshelf/features/tuner/pitch_detector.dart';

PitchResult pitch(int midi, {double cents = 0, double confidence = .99}) =>
    PitchResult(
      frequencyFromMidi(midi) * math.pow(2, cents / 1200),
      confidence,
    );

void main() {
  late NoteMatcher matcher;
  setUp(() => matcher = NoteMatcher());
  NoteMatchResult observe(PitchResult? detection, {int? expected = 69}) =>
      matcher.observe(expectedMidiPitch: expected, detectedPitch: detection);
  void confirm(int midi) {
    expect(
      observe(pitch(midi), expected: midi).status,
      NoteMatchStatus.insufficientEvidence,
    );
    expect(
      observe(pitch(midi), expected: midi).status,
      NoteMatchStatus.insufficientEvidence,
    );
    expect(
      observe(pitch(midi), expected: midi).status,
      NoteMatchStatus.matched,
    );
  }

  test('correct notes require consecutive matching frames', () {
    final first = observe(pitch(69));
    expect(first.matchingObservations, 1);
    expect(first.status, NoteMatchStatus.insufficientEvidence);
    expect(observe(pitch(69)).matchingObservations, 2);
    final result = observe(pitch(69));
    expect(result.status, NoteMatchStatus.matched);
    expect(result.centsDifference, closeTo(0, 1e-9));
    expect(result.matchingObservations, 3);
  });

  test('incorrect notes and exact octave errors are not matched', () {
    for (final midi in [57, 68, 70, 81]) {
      for (var i = 0; i < 4; i++) {
        expect(observe(pitch(midi)).status, NoteMatchStatus.notMatched);
      }
    }
    expect(observe(pitch(81)).centsDifference, closeTo(1200, 1e-9));
  });

  test(
    'slightly sharp and flat observations match within configured tolerance',
    () {
      for (final offset in [-20.0, 20.0]) {
        matcher.reset();
        for (var i = 0; i < 2; i++) {
          expect(
            observe(pitch(69, cents: offset)).status,
            NoteMatchStatus.insufficientEvidence,
          );
        }
        final result = observe(pitch(69, cents: offset));
        expect(result.status, NoteMatchStatus.matched);
        expect(result.centsDifference, closeTo(offset, 1e-8));
      }
      matcher = NoteMatcher(toleranceCents: 10);
      expect(observe(pitch(69, cents: 11)).status, NoteMatchStatus.notMatched);
      expect(observe(pitch(69, cents: -11)).status, NoteMatchStatus.notMatched);
    },
  );

  test(
    'tolerance boundaries are inclusive without accepting outside pitches',
    () {
      for (final offset in [-25.0, 25.0]) {
        matcher.reset();
        observe(pitch(69, cents: offset));
        observe(pitch(69, cents: offset));
        expect(
          observe(pitch(69, cents: offset)).status,
          NoteMatchStatus.matched,
        );
      }
      for (final offset in [-25.001, 25.001]) {
        matcher.reset();
        expect(
          observe(pitch(69, cents: offset)).status,
          NoteMatchStatus.notMatched,
        );
      }
    },
  );

  test(
    'silence, low confidence and invalid detections clear consecutive evidence',
    () {
      for (final invalid in <PitchResult?>[
        null,
        const PitchResult(0, 1),
        const PitchResult(-440, 1),
        const PitchResult(double.nan, 1),
        const PitchResult(double.infinity, 1),
        const PitchResult(440, double.nan),
        const PitchResult(440, double.infinity),
        const PitchResult(440, -1),
        const PitchResult(440, 1.01),
        pitch(69, confidence: .84),
      ]) {
        matcher.reset();
        observe(pitch(69));
        observe(pitch(69));
        expect(observe(invalid).status, NoteMatchStatus.insufficientEvidence);
        expect(observe(pitch(69)).matchingObservations, 1);
        expect(observe(pitch(69)).status, NoteMatchStatus.insufficientEvidence);
        expect(observe(pitch(69)).status, NoteMatchStatus.matched);
      }
    },
  );

  test(
    'incorrect and unstable pitches cannot accumulate matching evidence',
    () {
      observe(pitch(69));
      observe(pitch(69));
      observe(pitch(70));
      expect(observe(pitch(69)).matchingObservations, 1);
      matcher.reset();
      for (var i = 0; i < 10; i++) {
        expect(
          observe(pitch(69, cents: i.isEven ? -20 : 20)).status,
          NoteMatchStatus.insufficientEvidence,
        );
      }
      // A stable recovery needs a fresh run, not earlier unstable observations.
      expect(observe(pitch(69, cents: 20)).matchingObservations, 2);
      expect(observe(pitch(69, cents: 20)).status, NoteMatchStatus.matched);
    },
  );

  test(
    'confidence, stability and consecutive frame count are configurable',
    () {
      matcher = NoteMatcher(
        minimumConfidence: .95,
        requiredObservations: 2,
        stabilityCents: 5,
      );
      expect(
        observe(pitch(69, confidence: .94)).status,
        NoteMatchStatus.insufficientEvidence,
      );
      expect(
        observe(pitch(69, cents: 1, confidence: .95)).matchingObservations,
        1,
      );
      expect(
        observe(pitch(69, cents: 4, confidence: .95)).status,
        NoteMatchStatus.matched,
      );
    },
  );

  test('continuous sustained pitch confirms only once', () {
    confirm(69);
    for (var i = 0; i < 20; i++) {
      expect(observe(pitch(69)).status, NoteMatchStatus.insufficientEvidence);
    }
  });

  test('two no-pitch frames release a repeated note; one dropout does not', () {
    confirm(69);
    observe(null);
    expect(observe(pitch(69)).status, NoteMatchStatus.insufficientEvidence);
    observe(null);
    observe(null);
    confirm(69);
  });

  test('low confidence or invalid input does not rearm a sustained note', () {
    confirm(69);
    for (final invalid in [
      pitch(70, confidence: .1),
      const PitchResult(0, 1),
    ]) {
      observe(invalid);
      observe(invalid);
      expect(observe(pitch(69)).status, NoteMatchStatus.insufficientEvidence);
    }
  });

  test('release requires consecutive clearly different confident pitches', () {
    confirm(69);
    observe(pitch(71));
    observe(pitch(69));
    expect(observe(pitch(69)).status, NoteMatchStatus.insufficientEvidence);
    observe(pitch(71));
    observe(pitch(71));
    confirm(69);
  });

  test(
    'expected-note changes clear evidence but cannot bypass the sustain latch',
    () {
      observe(pitch(69));
      observe(pitch(69));
      expect(observe(pitch(70), expected: 70).matchingObservations, 1);
      expect(observe(pitch(69)).matchingObservations, 1);
      observe(pitch(69));
      expect(observe(pitch(69)).status, NoteMatchStatus.matched);
      observe(pitch(69), expected: 70);
      expect(observe(pitch(69)).status, NoteMatchStatus.insufficientEvidence);
    },
  );

  test('unknown and invalid expected notes cannot match', () {
    for (final expected in [null, -1, 128]) {
      expect(
        observe(pitch(69), expected: expected).status,
        NoteMatchStatus.insufficientEvidence,
      );
    }
    confirm(69);
  });

  test('restart reset clears pending evidence and the matched-note latch', () {
    observe(pitch(69));
    observe(pitch(69));
    matcher.reset();
    confirm(69);
    matcher.reset();
    confirm(69);
  });

  test(
    'evidence-only reset preserves sustain gating and clears partial evidence',
    () {
      observe(pitch(69));
      observe(pitch(69));
      matcher.reset(preserveSustain: true);
      confirm(69);
      matcher.reset(preserveSustain: true);
      for (var i = 0; i < 5; i++) {
        expect(observe(pitch(69)).status, NoteMatchStatus.insufficientEvidence);
      }
      observe(null);
      observe(null);
      confirm(69);
    },
  );

  test('invalid configurations are rejected at runtime', () {
    for (final value in [0.0, -1.0, 51.0, double.nan, double.infinity]) {
      expect(() => NoteMatcher(toleranceCents: value), throwsArgumentError);
    }
    for (final value in [0.0, -1.0, 1.1, double.nan]) {
      expect(() => NoteMatcher(minimumConfidence: value), throwsArgumentError);
    }
    expect(() => NoteMatcher(requiredObservations: 1), throwsArgumentError);
    expect(() => NoteMatcher(releaseObservations: 1), throwsArgumentError);
    expect(() => NoteMatcher(stabilityCents: double.nan), throwsArgumentError);
  });
}
