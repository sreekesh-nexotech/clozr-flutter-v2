import '../entities/course.dart';
import '../entities/learner_record.dart';
import '../entities/lms_activity.dart';
import '../entities/lms_stats.dart';

/// Abstract contract for LMS data. The presentation layer depends only on this;
/// whether data comes from a mock source or a REST API is an infrastructure
/// detail. Reads are async (mock mode resolves immediately); the LMS surfaces
/// still render synchronously from load-then-notify providers, so there are no
/// loading/skeleton states.
abstract class LmsRepository {
  Future<List<Course>> getCourses();
  Future<List<LearnerRecord>> getRecords();

  /// Everyone enrolled on one course, with their progress on it. Empty in
  /// mock mode (the seed records already carry real course ids) and on a
  /// permission refusal.
  Future<List<LearnerRecord>> getCourseLearners(String courseId);
  Future<List<LmsActivity>> getActivity();

  /// The Overview's headline figures. Null when unavailable (mock mode, or the
  /// `403` a non-admin gets on the dashboard), which the screen reads as
  /// "derive them from what is loaded", exactly as it did before.
  Future<LmsStats?> getStats();

  /// Persists the signed-in user's progress on one module (best-effort,
  /// fire-and-forget — the UI has already applied the optimistic update).
  /// [index] is the module's position within the course; [value] is 0–100.
  Future<void> setModuleProgress({
    required String courseId,
    required String moduleId,
    required int index,
    required int value,
  });

  /// Enrols [userIds] on [courseId]. Returns how many were newly enrolled —
  /// the server skips anyone already on the course. Throws on refusal so the
  /// caller can say why rather than toast a success that never happened.
  Future<int> assignCourse({
    required String courseId,
    required List<String> userIds,
  });

  /// Sends [userId] a reminder about [courseId]. A real notification on the
  /// learner's side (`LMSNudge`), not a local toast. Throws on refusal.
  Future<void> nudgeLearner({
    required String userId,
    required String courseId,
  });

  // ── Course writes (webapp course editor). Each throws on refusal so the
  // caller never reports a success the server did not confirm. ──

  /// Creates a draft course; returns its id.
  Future<String> createCourse({required String title});

  /// Saves the editor's course fields.
  Future<void> updateCourse(
    String courseId, {
    required String title,
    required String description,
    required bool sequential,
    required bool mandatory,
  });

  Future<void> publishCourse(String courseId);

  /// Moves a published course back to draft.
  Future<void> draftCourse(String courseId);

  Future<void> deleteCourse(String courseId);
}
