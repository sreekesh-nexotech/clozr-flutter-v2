import '../entities/course.dart';
import '../entities/learner_record.dart';
import '../entities/lms_activity.dart';

/// Abstract contract for LMS data. The presentation layer depends only on this;
/// whether data comes from a mock source or a REST API is an infrastructure
/// detail. Reads are async (mock mode resolves immediately); the LMS surfaces
/// still render synchronously from load-then-notify providers, so there are no
/// loading/skeleton states.
abstract class LmsRepository {
  Future<List<Course>> getCourses();
  Future<List<LearnerRecord>> getRecords();
  Future<List<LmsActivity>> getActivity();

  /// Persists the signed-in user's progress on one module (best-effort,
  /// fire-and-forget — the UI has already applied the optimistic update).
  /// [index] is the module's position within the course; [value] is 0–100.
  Future<void> setModuleProgress({
    required String courseId,
    required String moduleId,
    required int index,
    required int value,
  });
}
