import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/my_course.dart';
import '../../infrastructure/data_sources/remote/my_training_remote_ds.dart';

final myTrainingRemoteProvider = Provider<MyTrainingRemoteDataSource>(
  (ref) => MyTrainingRemoteDataSource(ref.watch(apiServiceProvider)),
);

/// My Trainings search text (server-side `?search=`).
final myCoursesSearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Bumped when a lesson completes, so My Trainings and the player refetch.
final myTrainingRefreshProvider = StateProvider<int>((ref) => 0);

/// The learner's published enrolments. Mock mode has no learner data.
final myCoursesProvider =
    FutureProvider.autoDispose.family<MyCoursesPage, String>((ref, search) {
  ref.watch(myTrainingRefreshProvider);
  if (!ApiConfig.apiEnabled) return const MyCoursesPage(results: []);
  return ref.watch(myTrainingRemoteProvider).fetchMyCourses(search: search);
});

final myCourseDetailProvider = FutureProvider.autoDispose
    .family<MyCourseDetail, String>((ref, enrollmentId) {
  ref.watch(myTrainingRefreshProvider);
  return ref.watch(myTrainingRemoteProvider).fetchMyCourse(enrollmentId);
});

/// The embed for one video on one enrolment, keyed `(videoResourceId, enrollmentId)`.
final videoViewProvider =
    FutureProvider.autoDispose.family<VideoView, (String, String)>((ref, key) {
  return ref.watch(myTrainingRemoteProvider).fetchVideoView(key.$1, key.$2);
});
