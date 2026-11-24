import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A detected fundamental frequency in Hz with a 0 to 1 [confidence].
@immutable
class PitchResult {
  const PitchResult(this.frequency, this.confidence);
  final double frequency;
  final double confidence;
}

/// The nearest equal-tempered note to a frequency, such as `E2 -3 cents`.
@immutable
class NoteMatch {
  const NoteMatch({
    required this.name,
    required this.octave,
    required this.cents,
  });
  final String name;
  final int octave;

  /// Offset from the note's exact pitch, in the range [-50, 50].
  final double cents;
  String get label => '$name$octave';
}

const _noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Default concert pitch for note and frequency conversions.
const double referenceA4 = 440;

/// Converts a frequency in Hz to a fractional MIDI note number.
double midiFromFrequency(double frequency, {double a4 = referenceA4}) =>
    69 + 12 * (math.log(frequency / a4) / math.ln2);

/// Converts a MIDI note number to its frequency in Hz.
double frequencyFromMidi(int midi, {double a4 = referenceA4}) =>
    a4 * math.pow(2, (midi - 69) / 12);

/// Returns the closest note to [frequency] and how far off it is in cents.
NoteMatch nearestNote(double frequency, {double a4 = referenceA4}) {
  final midiExact = midiFromFrequency(frequency, a4: a4);
  final midi = midiExact.round();
  return NoteMatch(
    name: _noteNames[midi % 12],
    octave: midi ~/ 12 - 1,
    cents: (midiExact - midi) * 100,
  );
}

/// Parses names like `E2` or `F#3` to a MIDI number, or null if invalid.
int? midiFromNoteName(String note) {
  final match = RegExp(r'^([A-Ga-g])([#b]?)(-?\d)$').firstMatch(note.trim());
  if (match == null) return null;
  const semitones = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  var value = semitones[match.group(1)!.toUpperCase()]!;
  if (match.group(2) == '#') value++;
  if (match.group(2) == 'b') value--;
  return (int.parse(match.group(3)!) + 1) * 12 + value;
}

/// Cents from [target] to [frequency]; positive means sharp.
double centsBetween(double frequency, double target) =>
    1200 * (math.log(frequency / target) / math.ln2);

/// YIN pitch detector working on mono samples in the range [-1, 1].
class PitchDetector {
  static const defaultMinFrequency = 25.0;
  static const defaultMaxFrequency = 1000.0;

  PitchDetector({
    required this.sampleRate,
    this.minFrequency = defaultMinFrequency,
    this.maxFrequency = defaultMaxFrequency,
    this.threshold = 0.15,
    this.minRms = 0.01,
  });

  final int sampleRate;

  /// Lowest and highest pitches searched for, in Hz.
  final double minFrequency;
  final double maxFrequency;

  /// YIN cutoff for accepting a period. Lower values are stricter.
  final double threshold;

  /// Inputs quieter than this root-mean-square level are ignored.
  final double minRms;

  /// Samples needed for a reliable estimate of the lowest supported pitch.
  int get windowSize => (sampleRate / minFrequency).ceil() * 2 + 2;

  /// Estimates the pitch of [samples], or returns null when the input is
  /// too quiet (below [minRms]), too short, or has no clear period.
  PitchResult? detect(Float64List samples) {
    final tauMax = (sampleRate / minFrequency).ceil();
    final tauMin = math.max(2, (sampleRate / maxFrequency).floor());
    final half = samples.length ~/ 2;
    if (half <= tauMax) return null;

    var energy = 0.0;
    for (var i = 0; i < samples.length; i++) {
      energy += samples[i] * samples[i];
    }
    if (math.sqrt(energy / samples.length) < minRms) return null;

    final diff = Float64List(tauMax + 1);
    for (var tau = 1; tau <= tauMax; tau++) {
      var sum = 0.0;
      for (var i = 0; i < half; i++) {
        final d = samples[i] - samples[i + tau];
        sum += d * d;
      }
      diff[tau] = sum;
    }

    // Cumulative mean normalised difference.
    final cmnd = Float64List(tauMax + 1);
    cmnd[0] = 1;
    var running = 0.0;
    for (var tau = 1; tau <= tauMax; tau++) {
      running += diff[tau];
      cmnd[tau] = running == 0 ? 1 : diff[tau] * tau / running;
    }

    var best = -1;
    for (var tau = tauMin; tau < tauMax; tau++) {
      if (cmnd[tau] < threshold) {
        while (tau + 1 < tauMax && cmnd[tau + 1] < cmnd[tau]) {
          tau++;
        }
        best = tau;
        break;
      }
    }
    if (best == -1) return null;

    // Parabolic interpolation for sub-sample accuracy.
    var refined = best.toDouble();
    if (best > 1 && best < tauMax) {
      final a = cmnd[best - 1];
      final b = cmnd[best];
      final c = cmnd[best + 1];
      final denom = a - 2 * b + c;
      if (denom != 0) refined += (a - c) / (2 * denom);
    }
    return PitchResult(sampleRate / refined, (1 - cmnd[best]).clamp(0.0, 1.0));
  }
}
