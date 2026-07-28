import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/entities/lms_activity.dart';
import '../../domain/repositories/lms_repository.dart';
import '../data_sources/local/lms_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class LmsRepositoryImpl implements LmsRepository {
  const LmsRepositoryImpl(this._local);

  final LmsMockDataSource _local;

  @override
  List<Course> getCourses() => _local.fetchCourses();

  @override
  List<LearnerRecord> getRecords() => _local.fetchRecords();

  @override
  List<LmsActivity> getActivity() => _local.fetchActivity();
}
