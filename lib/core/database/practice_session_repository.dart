import '../models/practice_session.dart';

abstract interface class PracticeSessionRepository {
  Future<void> save(PracticeSession session);
  Future<List<PracticeSession>> getAll();
  Future<void> clear();
}
