import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/database/practice_session_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/practice_session.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/practice_history_screen.dart';
import 'package:riffshelf/features/tabs/practice_session_screen.dart';
import 'package:riffshelf/features/tabs/practice_timeline.dart';
import 'package:riffshelf/features/tabs/timed_practice_scorer.dart';
import 'package:riffshelf/features/tuner/audio_input.dart';
import 'package:riffshelf/features/tuner/pitch_detector.dart';

class FakeAudioInput implements TunerAudioInput {
  FakeAudioInput([this.availability = MicrophoneStatus.available]);
  final MicrophoneStatus availability;
  StreamController<Uint8List> frames = StreamController<Uint8List>(
    onCancel: () async {},
  );
  int starts = 0;
  int stops = 0;

  @override
  int get sampleRate => 22050;

  @override
  Future<MicrophoneStatus> prepare() async => availability;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    frames = StreamController<Uint8List>(onCancel: () async {});
    return frames.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    unawaited(frames.close());
  }

  void emit(double frequency) {
    final samples = ByteData(3600);
    for (var i = 0; i < 1800; i++) {
      samples.setInt16(
        i * 2,
        (12000 * math.sin(2 * math.pi * frequency * i / sampleRate)).round(),
        Endian.little,
      );
    }
    if (frames.hasListener) frames.add(samples.buffer.asUint8List());
  }

  void emitSilence() {
    final samples = Uint8List(3600);
    if (frames.hasListener) frames.add(samples);
  }
}

class FakeHistoryRepository implements PracticeSessionRepository {
  final List<PracticeSession> sessions = [];

  @override
  Future<void> save(PracticeSession session) async => sessions.add(session);

  @override
  Future<List<PracticeSession>> getAll() async => List.unmodifiable(sessions);

  @override
  Future<void> clear() async => sessions.clear();
}

SavedTab createTestTab({
  bool includeChord = false,
  bool includeOverlap = false,
  bool includeTechnique = false,
  int bpm = 120,
}) {
  return SavedTab(
    title: 'Scoring Test Tab',
    artist: 'Tester',
    source: 'test',
    sourceUrl: '',
    instrument: InstrumentType.guitar,
    stringCount: 6,
    tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
    bpm: bpm,
    measures: [
      TabMeasure(
        number: 1,
        beats: [
          // Beat 0: String 1 fret 0 (High E4 = MIDI 64)
          TabBeat(
            position: 0,
            notes: [
              TabNote(
                stringNumber: 1,
                fret: 0,
                midiPitch: 64,
                technique: includeTechnique ? 'b' : null,
              ),
              if (includeChord)
                const TabNote(stringNumber: 2, fret: 0, midiPitch: 59),
            ],
          ),
          // Beat 2: String 1 fret 0 (High E4 = MIDI 64) - repeated note
          TabBeat(
            position: 2,
            notes: const [TabNote(stringNumber: 1, fret: 0, midiPitch: 64)],
          ),
          if (includeOverlap)
            TabBeat(
              position: 2.5,
              notes: const [TabNote(stringNumber: 2, fret: 1, midiPitch: 60)],
            ),
        ],
      ),
      const TabMeasure(
        number: 2,
        beats: [
          // Beat 4: String 2 fret 1 (C4 = MIDI 60)
          TabBeat(
            position: 0,
            notes: [TabNote(stringNumber: 2, fret: 1, midiPitch: 60)],
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('TimedPracticeScorer engine', () {
    test('correct pitch in tolerance window is scored as hit (green)', () {
      final tab = createTestTab();
      final timeline = PracticeTimeline.forScrolling(tab);
      final scorer = TimedPracticeScorer(
        timeline: timeline,
        bpm: 120,
        timingToleranceSeconds: 0.25, // 0.25s at 120bpm = 0.5 beats
      );
      scorer.isMicrophoneActive = true;

      // First note is at beat 0, window is [0.0, 0.5]
      scorer.updatePosition(0.1);
      final firstNote = timeline.events.first;
      expect(scorer.evaluationForNote(firstNote), TimedNoteEvaluation.neutral);

      // Supply 3 matching detections (MIDI 64: High E4 ~ 329.63 Hz)
      for (var i = 0; i < 3; i++) {
        scorer.observePitch(const PitchResult(329.63, 0.95));
      }

      expect(scorer.evaluationForNote(firstNote), TimedNoteEvaluation.hit);
      expect(scorer.hits, 1);
      expect(scorer.misses, 0);
      expect(scorer.accuracyPercentage, 100.0);
    });

    test('wrong pitch inside window remains pending, then missed (red) when window passes', () {
      final tab = createTestTab();
      final timeline = PracticeTimeline.forScrolling(tab);
      final scorer = TimedPracticeScorer(
        timeline: timeline,
        bpm: 120,
        timingToleranceSeconds: 0.25,
      );
      scorer.isMicrophoneActive = true;
      final firstNote = timeline.events.first;

      // At beat 0.1, wrong pitch (MIDI 60: C4 ~ 261.63 Hz) is played
      scorer.updatePosition(0.1);
      for (var i = 0; i < 3; i++) {
        scorer.observePitch(const PitchResult(261.63, 0.95));
      }
      // Note is still in window, remains neutral
      expect(scorer.evaluationForNote(firstNote), TimedNoteEvaluation.neutral);
      expect(scorer.hits, 0);
      expect(scorer.misses, 0);

      // Playhead advances past window end (> 0.5 beats)
      scorer.updatePosition(0.6);
      expect(scorer.evaluationForNote(firstNote), TimedNoteEvaluation.missed);
      expect(scorer.hits, 0);
      expect(scorer.misses, 1);
      expect(scorer.accuracyPercentage, 0.0);
    });

    test('late note (played after window passes) is not credited as hit', () {
      final tab = createTestTab();
      final timeline = PracticeTimeline.forScrolling(tab);
      final scorer = TimedPracticeScorer(
        timeline: timeline,
        bpm: 120,
        timingToleranceSeconds: 0.25,
      );
      scorer.isMicrophoneActive = true;
      final firstNote = timeline.events.first;

      // Playhead passes the first note window without any pitch
      scorer.updatePosition(0.6);
      expect(scorer.evaluationForNote(firstNote), TimedNoteEvaluation.missed);

      // User plays correct pitch late at beat 0.7
      scorer.updatePosition(0.7);
      for (var i = 0; i < 3; i++) {
        scorer.observePitch(const PitchResult(329.63, 0.95));
      }

      // First note stays missed
      expect(scorer.evaluationForNote(firstNote), TimedNoteEvaluation.missed);
      expect(scorer.hits, 0);
      expect(scorer.misses, 1);
    });

    test('repeated notes: held pitch does not falsely match second note', () {
      final tab = createTestTab();
      final timeline = PracticeTimeline.forScrolling(tab);
      final scorer = TimedPracticeScorer(
        timeline: timeline,
        bpm: 120,
        timingToleranceSeconds: 0.25,
      );
      scorer.isMicrophoneActive = true;

      final firstNote = timeline.events[0]; // beat 0, MIDI 64
      final secondNote = timeline.events[1]; // beat 2, MIDI 64

      // Hit note 1
      scorer.updatePosition(0.1);
      for (var i = 0; i < 3; i++) {
        scorer.observePitch(const PitchResult(329.63, 0.95));
      }
      expect(scorer.evaluationForNote(firstNote), TimedNoteEvaluation.hit);

      // Pitch is continuously sustained without release across beats 1 and 2
      scorer.updatePosition(1.0);
      scorer.observePitch(const PitchResult(329.63, 0.95));

      // At beat 2 (start of second note): pitch is still held
      scorer.updatePosition(2.0);
      for (var i = 0; i < 3; i++) {
        scorer.observePitch(const PitchResult(329.63, 0.95));
      }

      // NoteMatcher sustained protection prevents second note from matching
      expect(scorer.evaluationForNote(secondNote), TimedNoteEvaluation.neutral);

      // Advance past window of second note (> 2.5 beats)
      scorer.updatePosition(2.6);
      expect(scorer.evaluationForNote(secondNote), TimedNoteEvaluation.missed);
      expect(scorer.hits, 1);
      expect(scorer.misses, 1);
    });

    test('repeated notes: releasing pitch allows second note to match', () {
      final tab = createTestTab();
      final timeline = PracticeTimeline.forScrolling(tab);
      final scorer = TimedPracticeScorer(
        timeline: timeline,
        bpm: 120,
        timingToleranceSeconds: 0.25,
      );
      scorer.isMicrophoneActive = true;

      final firstNote = timeline.events[0]; // beat 0, MIDI 64
      final secondNote = timeline.events[1]; // beat 2, MIDI 64

      // Hit note 1
      scorer.updatePosition(0.1);
      for (var i = 0; i < 3; i++) {
        scorer.observePitch(const PitchResult(329.63, 0.95));
      }
      expect(scorer.evaluationForNote(firstNote), TimedNoteEvaluation.hit);

      // Release note 1 (silence / null frames)
      scorer.updatePosition(1.0);
      scorer.observePitch(null);
      scorer.observePitch(null);

      // Play note 2 at beat 2
      scorer.updatePosition(2.0);
      for (var i = 0; i < 3; i++) {
        scorer.observePitch(const PitchResult(329.63, 0.95));
      }

      expect(scorer.evaluationForNote(secondNote), TimedNoteEvaluation.hit);
      expect(scorer.hits, 2);
      expect(scorer.misses, 0);
    });

    test(
      'unsupported chords, techniques and overlaps remain neutral and unscored',
      () {
        final chordTab = createTestTab(includeChord: true);
        final chordTimeline = PracticeTimeline.forScrolling(chordTab);
        final scorer = TimedPracticeScorer(timeline: chordTimeline, bpm: 120);
        scorer.isMicrophoneActive = true;

        // Both notes at beat 0 form a chord -> neither should be eligible
        for (final event in chordTimeline.events.where(
          (e) => e.startBeat == 0,
        )) {
          expect(scorer.evaluationForNote(event), TimedNoteEvaluation.neutral);
        }

        // Advance past beat 0 window
        scorer.updatePosition(1.0);
        for (final event in chordTimeline.events.where(
          (e) => e.startBeat == 0,
        )) {
          expect(scorer.evaluationForNote(event), TimedNoteEvaluation.neutral);
        }
        expect(scorer.misses, 0); // Not counted as misses

        // Technique test
        final techTab = createTestTab(includeTechnique: true);
        final techTimeline = PracticeTimeline.forScrolling(techTab);
        final techScorer = TimedPracticeScorer(
          timeline: techTimeline,
          bpm: 120,
        );
        techScorer.isMicrophoneActive = true;
        techScorer.updatePosition(1.0);
        expect(
          techScorer.evaluationForNote(techTimeline.events.first),
          TimedNoteEvaluation.neutral,
        );
        expect(techScorer.misses, 0);
      },
    );

    test('inactive microphone produces 0 false misses', () {
      final tab = createTestTab();
      final timeline = PracticeTimeline.forScrolling(tab);
      final scorer = TimedPracticeScorer(timeline: timeline, bpm: 120);
      scorer.isMicrophoneActive =
          false; // Microphone permission denied or errored

      // Advance through entire section
      scorer.updatePosition(timeline.totalBeats);
      expect(scorer.misses, 0);
      expect(scorer.hits, 0);
      for (final event in timeline.events) {
        expect(scorer.evaluationForNote(event), TimedNoteEvaluation.neutral);
      }
    });

    test('seeking backwards resets notes at or after seek target', () {
      final tab = createTestTab();
      final timeline = PracticeTimeline.forScrolling(tab);
      final scorer = TimedPracticeScorer(timeline: timeline, bpm: 120);
      scorer.isMicrophoneActive = true;

      // Note 1 hit
      scorer.updatePosition(0.1);
      for (var i = 0; i < 3; i++) {
        scorer.observePitch(const PitchResult(329.63, 0.95));
      }
      expect(scorer.hits, 1);

      // Note 2 missed
      scorer.updatePosition(3.0);
      expect(scorer.misses, 1);

      // Seek back to beat 1.5 (before note 2)
      scorer.seekTo(1.5);
      expect(scorer.misses, 0); // Note 2 reset
      expect(scorer.hits, 1); // Note 1 kept

      // Seek back to beat 0.0
      scorer.seekTo(0.0);
      expect(scorer.hits, 0); // Note 1 reset
      expect(scorer.misses, 0);
    });

    test('loop wrap resets evaluations and stores last pass stats', () {
      final tab = createTestTab();
      final timeline = PracticeTimeline.forScrolling(tab);
      final scorer = TimedPracticeScorer(timeline: timeline, bpm: 120);
      scorer.isMicrophoneActive = true;

      // Complete attempt with 1 hit, 2 misses
      scorer.updatePosition(0.1);
      for (var i = 0; i < 3; i++) {
        scorer.observePitch(const PitchResult(329.63, 0.95));
      }
      scorer.updatePosition(timeline.totalBeats);
      expect(scorer.hits, 1);
      expect(scorer.misses, 2);

      // Wrap loop
      scorer.recordLoopWrap(0.0);
      expect(scorer.hits, 0);
      expect(scorer.misses, 0);
      expect(scorer.lastCompletedHits, 1);
      expect(scorer.lastCompletedMisses, 2);
      expect(scorer.lastCompletedAccuracy, closeTo(33.33, 0.1));
    });
  });

  group('PracticeSessionScreen timed practice integration', () {
    testWidgets(
      'shows live hits and misses and updates when notes are matched or missed',
      (tester) async {
        final tab = createTestTab();
        final fakeAudio = FakeAudioInput();
        final fakeHistory = FakeHistoryRepository();

        await tester.pumpWidget(
          MaterialApp(
            home: PracticeSessionScreen(
              tab: tab,
              inputFactory: () => fakeAudio,
              historyRepository: fakeHistory,
            ),
          ),
        );

        // Initial status in Timed scrolling mode
        expect(
          find.byKey(const ValueKey('timed-practice-status')),
          findsOneWidget,
        );
        expect(find.textContaining('Hits: 0 · Misses: 0'), findsOneWidget);

        // Start timed playback
        final playButton = find.byTooltip('Play');
        await tester.tap(playButton);
        await tester.pump();
        expect(fakeAudio.starts, 1);

        // Advance by 100ms, note at beat 0 is active (MIDI 64 High E = 329.63 Hz)
        await tester.pump(const Duration(milliseconds: 100));
        for (var i = 0; i < 3; i++) {
          fakeAudio.emit(329.63);
          await tester.pump(const Duration(milliseconds: 20));
        }

        // Verified hit!
        expect(find.textContaining('Hits: 1 · Misses: 0'), findsOneWidget);

        // Let time pass past beat 2 note without emitting pitch (miss)
        // At 120 BPM, 2 beats = 1.0 second
        await tester.pump(const Duration(milliseconds: 1500));
        expect(find.textContaining('Hits: 1 · Misses: 1'), findsOneWidget);

        // Scroll to end of section
        await tester.pump(const Duration(milliseconds: 3000));

        // End of section summary and Save button
        expect(find.textContaining('Section complete'), findsOneWidget);
        expect(find.textContaining('33.3% accuracy'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('save-timed-practice-results')),
          findsOneWidget,
        );

        // Tap Save results
        await tester.tap(
          find.byKey(const ValueKey('save-timed-practice-results')),
        );
        await tester.pumpAndSettle();

        // Dialog appears with stats
        expect(find.text('Save practice session?'), findsOneWidget);
        expect(
          find.textContaining('1 hits, 2 misses (33.3% accuracy)'),
          findsOneWidget,
        );

        // Save confirmation
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(fakeHistory.sessions, hasLength(1));
        final saved = fakeHistory.sessions.first;
        expect(saved.hits, 1);
        expect(saved.misses, 2);
        expect(saved.accuracy, closeTo(33.3, 0.1));
        expect(saved.confirmedNotes, 1);
      },
    );

    testWidgets(
      'microphone errors do not block scrolling or cause false misses',
      (tester) async {
        final tab = createTestTab();
        final brokenAudio = FakeAudioInput(MicrophoneStatus.permissionDenied);
        final fakeHistory = FakeHistoryRepository();

        await tester.pumpWidget(
          MaterialApp(
            home: PracticeSessionScreen(
              tab: tab,
              inputFactory: () => brokenAudio,
              historyRepository: fakeHistory,
            ),
          ),
        );

        // Tap play
        await tester.tap(find.byTooltip('Play'));
        await tester.pump();

        // Scrolling advances without pausing
        await tester.pump(const Duration(seconds: 2));

        // Scrolling continues, but 0 misses created
        expect(find.textContaining('Misses: 0'), findsOneWidget);
        expect(
          find.textContaining('scrolling continues without scoring'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PracticeHistoryScreen displays timed practice accuracy and stats',
      (tester) async {
        final fakeHistory = FakeHistoryRepository();
        fakeHistory.sessions.add(
          PracticeSession(
            title: 'Master of Riffs',
            artist: 'Riff Shelf',
            savedAt: DateTime.utc(2026, 2, 1),
            durationMilliseconds: 120000,
            startMeasure: 1,
            endMeasure: 4,
            markedComplete: true,
            confirmedNotes: 15,
            hits: 15,
            misses: 3,
            accuracy: 83.3,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(home: PracticeHistoryScreen(repository: fakeHistory)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Timed practice hits: 15'), findsOneWidget);
        expect(find.text('Timed practice misses: 3'), findsOneWidget);
        expect(find.text('Timed practice accuracy: 83.3%'), findsOneWidget);
        expect(
          find.textContaining('15 hits, 3 misses (83.3% accuracy)'),
          findsOneWidget,
        );
      },
    );
  });
}
