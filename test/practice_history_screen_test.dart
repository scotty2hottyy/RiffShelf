import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/database/practice_session_repository.dart';
import 'package:riffshelf/core/database/tab_repository.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/practice_session.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/practice_history_screen.dart';
import 'package:riffshelf/features/tabs/practice_session_screen.dart';
import 'package:riffshelf/screens/practice_screen.dart';

class EmptyTabs implements TabRepository {
  @override
  Future<List<SavedTab>> findTabs([
    TabFilter filter = const TabFilter(),
  ]) async => [];
  @override
  Future<SavedTab?> getById(int id) async => null;
  @override
  Future<SavedTab> save(SavedTab tab) => throw UnimplementedError();
  @override
  Future<Set<String>> allTags() async => {};
  @override
  Future<void> delete(int id) async {}
  @override
  Future<void> close() async {}
}

class MemoryHistory implements PracticeSessionRepository {
  final List<PracticeSession> sessions = [];
  bool failSave = false;
  bool failClear = false;

  @override
  Future<void> save(PracticeSession session) async {
    if (failSave) throw StateError('save failed');
    sessions.add(session);
  }

  @override
  Future<List<PracticeSession>> getAll() async => List.of(sessions.reversed);

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('clear failed');
    sessions.clear();
  }
}

class FakeStopwatch implements Stopwatch {
  int milliseconds = 0;
  @override
  bool isRunning = false;
  void advance(int value) {
    if (isRunning) milliseconds += value;
  }

  @override
  Duration get elapsed => Duration(milliseconds: milliseconds);
  @override
  int get elapsedMicroseconds => milliseconds * 1000;
  @override
  int get elapsedMilliseconds => milliseconds;
  @override
  int get elapsedTicks => milliseconds;
  @override
  int get frequency => 1000;
  @override
  void reset() => milliseconds = 0;
  @override
  void start() => isRunning = true;
  @override
  void stop() => isRunning = false;
}

void main() {
  const tab = SavedTab(
    title: 'Riff',
    artist: 'Artist',
    source: 'Test',
    sourceUrl: 'test',
    instrument: InstrumentType.guitar,
    stringCount: 6,
    tuning: ['E', 'A', 'D', 'G', 'B', 'E'],
    measures: [
      TabMeasure(
        number: 1,
        beats: [
          TabBeat(position: 0, notes: [TabNote(stringNumber: 1, fret: 3)]),
        ],
      ),
    ],
  );

  testWidgets('history is accessible from an empty practice library', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeScreen(
            repository: EmptyTabs(),
            historyRepository: MemoryHistory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Practice history'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No saved sessions'), findsOneWidget);
  });

  testWidgets('saving is optional and records the user-marked section', (
    tester,
  ) async {
    final history = MemoryHistory();
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeSessionScreen(tab: tab, historyRepository: history),
      ),
    );
    expect(history.sessions, isEmpty);
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-practice-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(history.sessions, isEmpty);

    await tester.tap(find.byKey(const ValueKey('save-practice-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark selected section as completed'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(history.sessions, hasLength(1));
    expect(history.sessions.single.markedComplete, isTrue);
    expect(history.sessions.single.startMeasure, 1);
    expect(history.sessions.single.confirmedNotes, 0);
    expect(find.text('Practice session saved locally.'), findsOneWidget);
  });

  testWidgets('recorded practice time excludes paused time', (tester) async {
    final history = MemoryHistory();
    final clock = FakeStopwatch();
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeSessionScreen(
          tab: tab,
          historyRepository: history,
          practiceStopwatch: clock,
        ),
      ),
    );
    final play = find.byKey(const ValueKey('practice-play-pause'));
    await tester.tap(play);
    await tester.pump();
    clock.advance(2500);
    await tester.tap(play);
    await tester.pump();
    clock.advance(10000);
    await tester.tap(play);
    await tester.pump();
    clock.advance(1000);
    await tester.tap(find.byKey(const ValueKey('save-practice-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(history.sessions.single.durationMilliseconds, 3500);
    expect(clock.isRunning, isFalse);
  });

  testWidgets('failed saves remain retryable and report the error', (
    tester,
  ) async {
    final history = MemoryHistory()..failSave = true;
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeSessionScreen(tab: tab, historyRepository: history),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('practice-play-pause')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-practice-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Could not save practice session.'), findsOneWidget);
    history.failSave = false;
    await tester.tap(find.byKey(const ValueKey('save-practice-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(history.sessions, hasLength(1));
  });

  testWidgets('history shows honest totals and confirms deletion', (
    tester,
  ) async {
    final history = MemoryHistory();
    await history.save(
      PracticeSession(
        title: 'Riff',
        artist: 'Artist',
        savedAt: DateTime.utc(2026, 1, 1),
        durationMilliseconds: 75000,
        startMeasure: 1,
        endMeasure: 2,
        markedComplete: true,
        confirmedNotes: 4,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: PracticeHistoryScreen(repository: history)),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 saved sessions'), findsOneWidget);
    expect(find.text('Practice time: 1 min 15 sec'), findsOneWidget);
    expect(find.textContaining('accuracy are unavailable'), findsOneWidget);
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(history.sessions, hasLength(1));
    history.failClear = true;
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('Could not clear practice history.'), findsOneWidget);
    expect(history.sessions, hasLength(1));
    history.failClear = false;
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(history.sessions, isEmpty);
    expect(find.textContaining('No saved sessions'), findsOneWidget);
  });
}
