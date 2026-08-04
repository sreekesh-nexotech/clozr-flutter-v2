import '../../../../core/network/app_error.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/entities/lms_activity.dart';
import '../../domain/repositories/lms_repository.dart';
import '../data_sources/remote/lms_remote_ds.dart';

/// API-backed [LmsRepository].
///
/// Caching is intentionally skipped for the LMS slice (no dedicated AppCache
/// box exists for it; the load-then-notify providers keep their seed on
/// failure instead). Orchestration only:
/// - courses are fetched single-flight so records can reuse the module counts;
/// - learner + activity endpoints are admin-only → a 403 degrades gracefully
///   (records fall back to just 'me'; the activity feed to empty).
class LmsApiRepository implements LmsRepository {
  LmsApiRepository(this._remote);

  final LmsRemoteDataSource _remote;

  Future<List<Course>>? _coursesFuture;

  Future<List<Course>> _courses() => _coursesFuture ??= _remote.fetchCourses();

  @override
  Future<List<Course>> getCourses() async {
    try {
      return await _courses();
    } on Object {
      _coursesFuture = null; // Allow a later retry instead of caching failure.
      rethrow;
    }
  }

  @override
  Future<List<LearnerRecord>> getRecords() async {
    // Best-effort course fetch first: module counts shape the 'me' record's
    // per-module arrays. A course failure must not sink the record itself.
    try {
      await _courses();
    } on Object {
      _coursesFuture = null;
    }
    final records = <LearnerRecord>[await _remote.fetchMyRecord()];
    try {
      records.addAll(await _remote.fetchLearnerRecords());
    } on AppError {
      // Admin-only endpoint — non-admins simply see their own record.
    }
    return records;
  }

  @override
  Future<List<LmsActivity>> getActivity() async {
    try {
      return await _remote.fetchActivity();
    } on AppError catch (e) {
      if (e.type == AppErrorType.forbidden || e.type == AppErrorType.notFound) {
        return const []; // Admin-only feed — hidden, not fatal.
      }
      rethrow;
    }
  }

  @override
  Future<void> setModuleProgress({
    required String courseId,
    required String moduleId,
    required int index,
    required int value,
  }) async {
    // Fire-and-forget by contract: the notifier already applied the optimistic
    // update, so a failed write must never surface (or crash unawaited).
    try {
      await _remote.postModuleProgress(
        courseId: courseId,
        moduleId: moduleId,
        index: index,
        value: value,
      );
    } on Object {
      // Swallowed — progress re-syncs on the next records fetch.
    }
  }
}
