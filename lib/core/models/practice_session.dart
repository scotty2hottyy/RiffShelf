/// One saved practice session for a tab, stored only on this device.
///
/// [hits], [misses], and [accuracy] are only set by timed scoring; they
/// are null for scrolling and note-by-note sessions.
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
    this.hits,
    this.misses,
    this.accuracy,
  });

  final String title;
  final String artist;
  final DateTime savedAt;

  /// Time spent with playback or note following active.
  final int durationMilliseconds;

  /// First and last measure of the selected section, or null when the tab
  /// has no measures.
  final int? startMeasure;
  final int? endMeasure;

  /// Set by the user; the app never infers completion.
  final bool markedComplete;

  /// Notes confirmed in note-by-note mode, including repeats. For timed
  /// sessions this is the number of hits.
  final int confirmedNotes;
  final int? hits;
  final int? misses;
  final double? accuracy;

  Map<String, Object?> toDatabaseMap() => {
    'title': title,
    'artist': artist,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'duration_ms': durationMilliseconds,
    'start_measure': startMeasure,
    'end_measure': endMeasure,
    'marked_complete': markedComplete ? 1 : 0,
    'confirmed_notes': confirmedNotes,
    if (hits != null) 'hits': hits,
    if (misses != null) 'misses': misses,
    if (accuracy != null) 'accuracy': accuracy,
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
        hits: row['hits'] as int?,
        misses: row['misses'] as int?,
        accuracy: (row['accuracy'] as num?)?.toDouble(),
      );
}

/// All-time totals shown on the practice history screen.
class PracticeHistorySummary {
  PracticeHistorySummary(Iterable<PracticeSession> sessions)
    : sessions = sessions.length,
      durationMilliseconds = sessions.fold(
        0,
        (sum, session) => sum + session.durationMilliseconds,
      ),
      completedSections = sessions.where((s) => s.markedComplete).length,
      confirmedNotes = sessions.fold(0, (sum, s) => sum + s.confirmedNotes),
      totalHits = sessions.fold(0, (sum, s) => sum + (s.hits ?? 0)),
      totalMisses = sessions.fold(0, (sum, s) => sum + (s.misses ?? 0)),
      timedSessions = sessions
          .where((s) => s.hits != null || s.misses != null)
          .length;

  final int sessions;
  final int durationMilliseconds;
  final int completedSections;
  final int confirmedNotes;
  final int totalHits;
  final int totalMisses;
  final int timedSessions;

  /// Percentage of timed notes hit, or null if nothing was scored.
  double? get averageAccuracy {
    final total = totalHits + totalMisses;
    if (total == 0) return null;
    return (totalHits / total) * 100.0;
  }
}
