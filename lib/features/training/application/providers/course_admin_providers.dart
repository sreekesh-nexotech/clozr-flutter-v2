import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/course.dart';
import '../../infrastructure/data_sources/remote/course_admin_remote_ds.dart';
import 'lms_providers.dart';

final courseAdminRemoteProvider = Provider<CourseAdminRemoteDataSource>(
  (ref) => CourseAdminRemoteDataSource(ref.watch(apiServiceProvider)),
);

/// The course detail, fetched fresh on every open (and after every write) —
/// never the cached list row, so a course deleted elsewhere reads "Course not
/// found." instead of live buttons on stale data. Mock mode reads the seed.
final courseDetailProvider =
    FutureProvider.autoDispose.family<Course?, String>((ref, id) {
  ref.watch(apiWriteTickProvider);
  if (!ApiConfig.apiEnabled) return ref.watch(lmsCourseByIdProvider(id));
  return ref.watch(courseAdminRemoteProvider).fetchCourse(id);
});

/// "Assigned learners" for one course, with the server's status per learner.
final courseLearnerRowsProvider = FutureProvider.autoDispose
    .family<List<CourseLearnerRow>, String>((ref, courseId) {
  ref.watch(apiWriteTickProvider);
  if (!ApiConfig.apiEnabled) return const [];
  return ref.watch(courseAdminRemoteProvider).fetchLearners(courseId);
});

/// The org's users for the Assign course sheet.
final assignableUsersProvider =
    FutureProvider.autoDispose<List<AssignableUser>>((ref) {
  if (!ApiConfig.apiEnabled) return const [];
  return ref.watch(courseAdminRemoteProvider).fetchUsers();
});

/// The org-wide Learners table, re-read after every write (assign, nudge).
final learnerSummariesProvider =
    FutureProvider.autoDispose<List<LearnerSummary>>((ref) {
  ref.watch(apiWriteTickProvider);
  if (!ApiConfig.apiEnabled) return const [];
  return ref.watch(courseAdminRemoteProvider).fetchAllLearners();
});
