class PracticeSession {
  const PracticeSession({
    required this.title,
    required this.artist,
    required this.savedAt,
    required this.durationMilliseconds,
    required this.startMeasure,
    required this.endMeasure,
    required this.markedComplete,
    required this.confirmedNotes,
  });

  final String title;
  final String artist;
  final DateTime savedAt;
  final int durationMilliseconds;
  final int? startMeasure;
  final int? endMeasure;
  final bool markedComplete;
  final int confirmedNotes;

  Map<String, Object?> toDatabaseMap() => {
    'title': title,
    'artist': artist,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'duration_ms': durationMilliseconds,
    'start_measure': startMeasure,
    'end_measure': endMeasure,
    'marked_complete': markedComplete ? 1 : 0,
    'confirmed_notes': confirmedNotes,
  };

  factory PracticeSession.fromDatabaseMap(Map<String, Object?> row) =>
      PracticeSession(
        title: row['title'] as String,
        artist: row['artist'] as String,
        savedAt: DateTime.parse(row['saved_at'] as String),
        durationMilliseconds: row['duration_ms'] as int,
        startMeasure: row['start_measure'] as int?,
        endMeasure: row['end_measure'] as int?,
        markedComplete: row['marked_complete'] == 1,
        confirmedNotes: row['confirmed_notes'] as int,
      );
}

class PracticeHistorySummary {
  PracticeHistorySummary(Iterable<PracticeSession> sessions)
    : sessions = sessions.length,
      durationMilliseconds = sessions.fold(
        0,
        (sum, session) => sum + session.durationMilliseconds,
      ),
      completedSections = sessions.where((s) => s.markedComplete).length,
      confirmedNotes = sessions.fold(0, (sum, s) => sum + s.confirmedNotes);

  final int sessions;
  final int durationMilliseconds;
  final int completedSections;
  final int confirmedNotes;
}
