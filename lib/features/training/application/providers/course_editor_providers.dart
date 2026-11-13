import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_providers.dart';
import '../../infrastructure/data_sources/remote/course_editor_remote_ds.dart';

final courseEditorRemoteProvider = Provider<CourseEditorRemoteDataSource>(
  (ref) => CourseEditorRemoteDataSource(ref.watch(apiServiceProvider)),
);

/// The course being edited, read fresh from `GET /lms/courses/{id}/`;
/// invalidated after every editor write so modules, videos, resources and the
/// staged thumbnail always show the server's state.
final editorCourseProvider =
    FutureProvider.autoDispose.family<EditorCourse, String>(
  (ref, id) => ref.watch(courseEditorRemoteProvider).fetchCourse(id),
);
