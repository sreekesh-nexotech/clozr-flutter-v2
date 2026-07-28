import '../entities/course.dart';
import '../entities/learner_record.dart';
import '../entities/lms_activity.dart';

/// Abstract contract for LMS data. The presentation layer depends only on this;
/// whether data comes from a mock source or a REST API is an infrastructure
/// detail. Reads are synchronous because progress is held in a live notifier
/// seeded from these — the LMS surfaces have no loading/skeleton states.
abstract class LmsRepository {
  List<Course> getCourses();
  List<LearnerRecord> getRecords();
  List<LmsActivity> getActivity();
}
