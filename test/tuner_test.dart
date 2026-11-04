import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/tuning.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/features/tuner/audio_input.dart';
import 'package:riffshelf/features/tuner/pitch_detector.dart';
import 'package:riffshelf/features/tuner/tuner_controller.dart';
import 'package:riffshelf/features/tuner/tuning_store.dart';
import 'package:riffshelf/screens/tuner_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class FakeInput implements TunerAudioInput {
  FakeInput(this.status);
  final MicrophoneStatus status;
  final controller = StreamController<Uint8List>();
  int starts = 0;
  int stops = 0;
  int disposals = 0;

  @override
  int get sampleRate => 22050;
  @override
  Future<MicrophoneStatus> prepare() async => status;
  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class FakeSettingsStore implements TunerSettingsStore {
  TunerSettings settings = const TunerSettings();

  @override
  Future<TunerSettings> load() async => settings;

  @override
  Future<void> save(TunerSettings value) async {
    settings = value;
  }
}

Float64List sine(double hz, int n, int rate) => Float64List.fromList([
  for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * hz * i / rate),
]);

Uint8List pcm(Float64List samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, (samples[i] * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

void emitPitch(FakeInput input, double hz) {
  input.controller.add(pcm(sine(hz, 22050, input.sampleRate)));
}

void main() {
  group('Tuner tunings', () {
    test('preset notes follow low-to-high guitar and bass string order', () {
      expect(TunerPresets.guitarStandard.notes, [
        'E2',
        'A2',
        'D3',
        'G3',
        'B3',
        'E4',
      ]);
      expect(TunerPresets.dropD.notes, ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']);
      expect(TunerPresets.dadgad.notes, ['D2', 'A2', 'D3', 'G3', 'A3', 'D4']);
      expect(TunerPresets.openG.notes, ['D2', 'G2', 'D3', 'G3', 'B3', 'D4']);
      expect(TunerPresets.bassStandard.notes, ['E1', 'A1', 'D2', 'G2']);
      expect(TunerPresets.bassDropD.notes, ['D1', 'A1', 'D2', 'G2']);
      expect(TunerPresets.bassFiveString.notes, ['B0', 'E1', 'A1', 'D2', 'G2']);
    });

    test('A4 reference and preset frequencies use the specified octave', () {
      expect(frequencyFromMidi(midiFromNoteName('A4')!), 440);
      expect(
        frequencyFromMidi(midiFromNoteName('E2')!),
        closeTo(82.4069, 0.001),
      );
      expect(
        frequencyFromMidi(midiFromNoteName('E1')!),
        closeTo(41.2034, 0.001),
      );
      expect(
        frequencyFromMidi(midiFromNoteName('B0')!),
        closeTo(30.8677, 0.001),
      );
    });

    test('validates names, counts, notes, and detector range', () {
      expect(
        tuningValidationError('Seven', InstrumentType.guitar, [
          'B1',
          'E2',
          'A2',
          'D3',
          'G3',
          'B3',
          'E4',
        ]),
        isNull,
      );
      expect(
        tuningValidationError('Five', InstrumentType.bass, [
          'B0',
          'E1',
          'A1',
          'D2',
          'G2',
        ]),
        isNull,
      );
      expect(
        tuningValidationError(
          '',
          InstrumentType.guitar,
          TunerPresets.guitarStandard.notes,
        ),
        isNotNull,
      );
      expect(
        tuningValidationError('Bad', InstrumentType.bass, ['E1', 'A1', 'D2']),
        isNotNull,
      );
      expect(
        tuningValidationError('Bad', InstrumentType.guitar, [
          'H2',
          'A2',
          'D3',
          'G3',
          'B3',
          'E4',
        ]),
        isNotNull,
      );
      expect(
        tuningValidationError('Bad', InstrumentType.guitar, [
          'C0',
          'A2',
          'D3',
          'G3',
          'B3',
          'E4',
        ]),
        isNotNull,
      );
    });

    test(
      'custom tunings and selected id serialize and reject bad stored data',
      () {
        const custom = CustomTuning(
          id: 'one',
          preset: TuningPreset(
            name: 'Low B',
            instrument: InstrumentType.bass,
            notes: ['B0', 'E1', 'A1', 'D2', 'G2'],
          ),
        );
        const settings = TunerSettings(
          customTunings: [custom],
          selectedId: 'one',
        );
        final restored = TunerSettings.fromJson(jsonEncode(settings.toJson()));
        expect(restored.selectedId, 'one');
        expect(restored.customTunings.single.preset.notes, custom.preset.notes);
        expect(TunerSettings.fromJson('{bad').customTunings, isEmpty);
      },
    );

    test('local settings survive a new store instance', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      await LocalTunerSettingsStore().save(
        const TunerSettings(selectedId: 'preset:bass:Bass Standard'),
      );
      final restored = await LocalTunerSettingsStore().load();
      expect(restored.selectedId, 'preset:bass:Bass Standard');
    });
  });

  group('PitchDetector', () {
    test('detects guitar and bass pitches', () {
      final detector = PitchDetector(sampleRate: 22050);
      for (final hz in [41.2, 82.41, 110.0, 196.0, 329.63]) {
        final result = detector.detect(sine(hz, detector.windowSize, 22050));
        expect(result, isNotNull, reason: '$hz');
        expect(result!.frequency, closeTo(hz, hz * 0.01), reason: '$hz');
      }
    });

    test('ignores silence', () {
      final detector = PitchDetector(sampleRate: 22050);
      expect(detector.detect(Float64List(detector.windowSize)), isNull);
    });

    test('maps frequencies to notes', () {
      final note = nearestNote(82.41);
      expect(note.label, 'E2');
      expect(note.cents.abs(), lessThan(1));
      expect(midiFromNoteName('A4'), 69);
    });
  });

  group('TunerScreen', () {
    Future<void> pumpTuner(WidgetTester tester, FakeInput input) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TunerScreen(
              inputFactory: () => input,
              settingsStore: FakeSettingsStore(),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Start tuning'));
    }

    testWidgets('explains when there is no microphone', (tester) async {
      await pumpTuner(tester, FakeInput(MicrophoneStatus.noMicrophone));
      await tester.tap(find.text('Start tuning'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No microphone was found'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    for (final (width, twoRows) in [(393.0, true), (430.0, false)]) {
      testWidgets('lays out six strings at $width pixels', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpTuner(tester, FakeInput(MicrophoneStatus.available));

        final first = find.byKey(const Key('tuner-strings-first-row'));
        final second = find.byKey(const Key('tuner-strings-second-row'));
        final single = find.byKey(const Key('tuner-strings-single-row'));
        if (twoRows) {
          expect(first, findsOneWidget);
          expect(second, findsOneWidget);
          expect(single, findsNothing);
          expect(
            find.descendant(of: first, matching: find.byType(Text)),
            findsNWidgets(3),
          );
          expect(
            find.descendant(of: second, matching: find.byType(Text)),
            findsNWidgets(3),
          );
          expect(tester.getCenter(first).dx, closeTo(width / 2, 1));
          expect(tester.getCenter(second).dx, closeTo(width / 2, 1));
        } else {
          expect(single, findsOneWidget);
          expect(first, findsNothing);
          expect(second, findsNothing);
          expect(
            find.descendant(of: single, matching: find.byType(Text)),
            findsNWidgets(6),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('explains when permission is denied', (tester) async {
      await pumpTuner(tester, FakeInput(MicrophoneStatus.permissionDenied));
      await tester.tap(find.text('Start tuning'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Microphone access is turned off'),
        findsOneWidget,
      );
    });

    testWidgets('shows the detected string', (tester) async {
      final input = FakeInput(MicrophoneStatus.available);
      await pumpTuner(tester, input);
      await tester.tap(find.text('Start tuning'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Stop'), findsOneWidget);

      final samples = sine(110.0, 22050, 22050);
      input.controller.add(pcm(samples));
      input.controller.add(pcm(samples));
      await tester.pump(const Duration(milliseconds: 10));

      expect(
        tester.widget<Text>(find.byKey(const Key('tuner-target-note'))).data,
        'A2',
      );
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
    });

    testWidgets('locks a string and returns to automatic detection', (
      tester,
    ) async {
      final input = FakeInput(MicrophoneStatus.available);
      await pumpTuner(tester, input);
      await tester.tap(find.byKey(const Key('tuner-string-5-E4')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('tuner-target-note'))).data,
        'E4',
      );
      expect(find.text('Automatic detection'), findsOneWidget);

      await tester.ensureVisible(find.text('Start tuning'));
      await tester.tap(find.text('Start tuning'));
      await tester.pump();
      emitPitch(input, 110);
      emitPitch(input, 110);
      await tester.pump();
      expect(find.textContaining('Detected A2'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('tuner-target-note'))).data,
        'E4',
      );

      await tester.ensureVisible(find.byKey(const Key('tuner-automatic')));
      await tester.tap(find.byKey(const Key('tuner-automatic')));
      await tester.pump();
      emitPitch(input, 110);
      emitPitch(input, 110);
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('tuner-target-note'))).data,
        'A2',
      );
    });

    testWidgets('releases the microphone when the screen is disposed', (
      tester,
    ) async {
      final input = FakeInput(MicrophoneStatus.available);
      await pumpTuner(tester, input);
      await tester.tap(find.text('Start tuning'));
      await tester.pump();
      expect(input.starts, 1);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      expect(input.stops, greaterThan(0));
      expect(input.disposals, 1);
    });

    testWidgets('switches guitar and bass strings and restores last preset', (
      tester,
    ) async {
      final store = FakeSettingsStore();
      final input = FakeInput(MicrophoneStatus.available);
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TunerScreen(
              key: UniqueKey(),
              inputFactory: () => input,
              settingsStore: store,
            ),
          ),
        ),
      );
      await show();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bass').first);
      await tester.pump();
      expect(find.byKey(const Key('tuner-string-0-E1')), findsOneWidget);
      expect(find.byKey(const Key('tuner-string-5-E4')), findsNothing);
      expect(store.settings.selectedId, contains('bass'));
      await show();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tuner-string-0-E1')), findsOneWidget);
      expect(find.byKey(const Key('tuner-string-5-E4')), findsNothing);
    });

    testWidgets('creates, edits, restores, and deletes a custom tuning', (
      tester,
    ) async {
      final store = FakeSettingsStore();
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TunerScreen(
              key: UniqueKey(),
              inputFactory: () => FakeInput(MicrophoneStatus.available),
              settingsStore: store,
            ),
          ),
        ),
      );
      await show();
      await tester.pumpAndSettle();
      await tester.tap(find.text('New tuning'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('tuning-name')),
        'Acoustic open',
      );
      await tester.enterText(find.byKey(const Key('tuning-note-0')), 'D2');
      await tester.tap(find.text('Save tuning'));
      await tester.pumpAndSettle();
      expect(store.settings.customTunings.single.preset.name, 'Acoustic open');
      expect(store.settings.customTunings.single.preset.notes.first, 'D2');
      expect(find.text('Edit tuning'), findsOneWidget);

      await tester.tap(find.text('Edit tuning'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('tuning-name')),
        'Open variation',
      );
      await tester.enterText(find.byKey(const Key('tuning-note-1')), 'G2');
      await tester.tap(find.text('Save tuning'));
      await tester.pumpAndSettle();
      expect(store.settings.customTunings.single.preset.notes[1], 'G2');

      await show();
      await tester.pumpAndSettle();
      expect(find.text('Open variation'), findsOneWidget);
      expect(find.byKey(const Key('tuner-string-0-D2')), findsOneWidget);
      await tester.tap(find.text('Delete tuning'));
      await tester.pumpAndSettle();
      expect(store.settings.customTunings, isEmpty);
      expect(find.byKey(const Key('tuner-string-0-E2')), findsOneWidget);
    });

    testWidgets('rejects invalid custom note before saving', (tester) async {
      final store = FakeSettingsStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TunerScreen(
              inputFactory: () => FakeInput(MicrophoneStatus.available),
              settingsStore: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New tuning'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tuning-note-0')), 'H9');
      await tester.tap(find.text('Save tuning'));
      await tester.pump();
      expect(find.textContaining('Use notes from A0'), findsOneWidget);
      expect(store.settings.customTunings, isEmpty);
    });

    testWidgets('fixed arrangement ignores the saved standalone selection', (
      tester,
    ) async {
      final store = FakeSettingsStore()
        ..settings = const TunerSettings(
          selectedId: 'preset:bass:Bass Standard',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TunerScreen(
              preset: TunerPresets.openG,
              inputFactory: () => FakeInput(MicrophoneStatus.available),
              settingsStore: store,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('tuner-string-0-D2')), findsOneWidget);
      expect(find.byKey(const Key('tuner-string-0-E1')), findsNothing);
      expect(find.text('New tuning'), findsNothing);
    });

    testWidgets('shows all strings in a twelve-string custom tuning', (
      tester,
    ) async {
      final store = FakeSettingsStore()
        ..settings = const TunerSettings(
          customTunings: [
            CustomTuning(
              id: 'twelve',
              preset: TuningPreset(
                name: 'Twelve',
                instrument: InstrumentType.guitar,
                notes: [
                  'E2',
                  'E2',
                  'A2',
                  'A2',
                  'D3',
                  'D3',
                  'G3',
                  'G3',
                  'B3',
                  'B3',
                  'E4',
                  'E4',
                ],
              ),
            ),
          ],
          selectedId: 'twelve',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TunerScreen(
              inputFactory: () => FakeInput(MicrophoneStatus.available),
              settingsStore: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tuner-string-0-E2')), findsOneWidget);
      expect(find.byKey(const Key('tuner-string-1-E2')), findsOneWidget);
      expect(find.byKey(const Key('tuner-string-11-E4')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('TunerController', () {
    test('maps guitar and bass pitch, cents, and intonation', () async {
      final input = FakeInput(MicrophoneStatus.available);
      final tuner = TunerController(input: input);
      await tuner.start();
      for (final (preset, frequency, target, cents) in [
        (TunerPresets.guitarStandard, 110.0, 'A2', 0.0),
        (TunerPresets.guitarStandard, 110 * math.pow(2, 12 / 1200), 'A2', 12.0),
        (
          TunerPresets.bassStandard,
          41.2034 * math.pow(2, -15 / 1200),
          'E1',
          -15.0,
        ),
        (TunerPresets.bassFiveString, 30.8677, 'B0', 0.0),
      ]) {
        tuner.preset = preset;
        emitPitch(input, frequency.toDouble());
        emitPitch(input, frequency.toDouble());
        await Future<void>.delayed(Duration.zero);
        expect(tuner.reading?.targetNote, target);
        expect(tuner.reading!.targetCents, closeTo(cents, 2));
        expect(tuner.reading!.inTune, cents.abs() <= 5);
      }
      await tuner.stop();
      tuner.dispose();
    });

    test('rejects silence, noise, and alternating pitches', () async {
      final input = FakeInput(MicrophoneStatus.available);
      final tuner = TunerController(input: input);
      await tuner.start();
      emitPitch(input, 110);
      await Future<void>.delayed(Duration.zero);
      expect(tuner.reading, isNull);
      emitPitch(input, 146.83);
      await Future<void>.delayed(Duration.zero);
      expect(tuner.reading, isNull);
      emitPitch(input, 110);
      await Future<void>.delayed(Duration.zero);
      expect(tuner.reading, isNull);
      emitPitch(input, 110);
      await Future<void>.delayed(Duration.zero);
      expect(tuner.reading, isNotNull);
      input.controller.add(pcm(Float64List(22050)));
      await Future<void>.delayed(Duration.zero);
      expect(tuner.reading, isNull);
      var seed = 1;
      final noise = Float64List.fromList(
        List.generate(22050, (_) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          return (seed / 0x7fffffff - 0.5) * 0.4;
        }),
      );
      input.controller.add(pcm(noise));
      input.controller.add(pcm(noise));
      await Future<void>.delayed(Duration.zero);
      expect(tuner.reading, isNull);
      await tuner.stop();
      tuner.dispose();
    });

    test(
      'permission denial does not start capture; stop and dispose release it',
      () async {
        final denied = FakeInput(MicrophoneStatus.permissionDenied);
        final blocked = TunerController(input: denied);
        await blocked.start();
        expect(blocked.status, TunerStatus.permissionDenied);
        expect(denied.starts, 0);
        blocked.dispose();

        final input = FakeInput(MicrophoneStatus.available);
        final tuner = TunerController(input: input);
        await tuner.start();
        expect(input.starts, 1);
        await tuner.stop();
        expect(input.stops, greaterThan(0));
        expect(tuner.reading, isNull);
        tuner.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(input.disposals, 1);
      },
    );
  });
}
