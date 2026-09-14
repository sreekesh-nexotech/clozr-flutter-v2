import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/entities/lms_activity.dart';
import '../../domain/entities/lms_stats.dart';
import '../../domain/repositories/lms_repository.dart';
import '../data_sources/local/lms_mock_ds.dart';

/// Mock-backed implementation. The API twin is `LmsApiRepository`; the
/// interface and every caller stay the same.
class LmsRepositoryImpl implements LmsRepository {
  const LmsRepositoryImpl(this._local);

  final LmsMockDataSource _local;

  @override
  Future<List<Course>> getCourses() => Future.value(_local.fetchCourses());

  @override
  Future<List<LearnerRecord>> getRecords() => Future.value(_local.fetchRecords());

  @override
  Future<List<LmsActivity>> getActivity() => Future.value(_local.fetchActivity());

  /// No dashboard endpoint in mock mode; null keeps the prototype's derived
  /// tiles exactly as they were.
  /// Mock records already carry real course ids, so the screen's own join
  /// over [getRecords] finds everyone; nothing extra to fetch.
  @override
  Future<List<LearnerRecord>> getCourseLearners(String courseId) async =>
      const [];

  @override
  Future<LmsStats?> getStats() => Future.value();

  @override
  Future<void> setModuleProgress({
    required String courseId,
    required String moduleId,
    required int index,
    required int value,
  }) =>
      Future.value(); // Mock progress lives in the notifier only.

  /// Mock mode has no server to enrol on; report everyone as enrolled so the
  /// flow completes the same way it does live.
  /// Nothing to notify in mock mode; the toast alone is the whole effect.
  @override
  Future<void> nudgeLearner({
    required String userId,
    required String courseId,
  }) =>
      Future.value();

  @override
  Future<int> assignCourse({
    required String courseId,
    required List<String> userIds,
  }) async =>
      userIds.length;
}
