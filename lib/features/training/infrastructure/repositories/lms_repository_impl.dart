import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/entities/lms_activity.dart';
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

  @override
  Future<void> setModuleProgress({
    required String courseId,
    required String moduleId,
    required int index,
    required int value,
  }) =>
      Future.value(); // Mock progress lives in the notifier only.
}
