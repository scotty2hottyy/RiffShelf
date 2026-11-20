import '../models/practice_session.dart';

/// Device-local storage for saved practice sessions.
abstract interface class PracticeSessionRepository {
  /// Adds [session] to the practice history.
  Future<void> save(PracticeSession session);

  /// Returns every saved session.
  Future<List<PracticeSession>> getAll();

  /// Deletes all practice history.
  Future<void> clear();
}
