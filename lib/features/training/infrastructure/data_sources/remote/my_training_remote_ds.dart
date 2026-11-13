import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../domain/entities/my_course.dart';

/// The learner endpoints (`/lms/my-courses/`, the video view and progress).
/// Server-exempt from the mandatory-course block, so a blocked learner can
/// still reach and finish the course. Mappers are static for tests.
class MyTrainingRemoteDataSource {
  MyTrainingRemoteDataSource(this._api);

  final ApiService _api;

  static String _view(String videoResourceId) =>
      '/lms/video-resources/$videoResourceId/view/';
  static String _progress(String videoResourceId) =>
      '/lms/video-resources/$videoResourceId/progress/';

  /// Server-side title search (`?search=`), as on the webapp.
  Future<MyCoursesPage> fetchMyCourses({String search = ''}) async {
    final body = await _api.get(ApiEndpoints.myCourses, query: {
      if (search.trim().isNotEmpty) 'search': search.trim(),
    });
    return mapPage(body);
  }

  Future<MyCourseDetail> fetchMyCourse(String enrollmentId) async =>
      mapDetail(await _api.get(ApiEndpoints.myCourse(enrollmentId)));

  Future<VideoView> fetchVideoView(
          String videoResourceId, String enrollmentId) async =>
      mapView(await _api
          .get(_view(videoResourceId), query: {'enrollment_id': enrollmentId}));

  /// Heartbeat / completion. Returns whether the server now counts the video
  /// complete — it auto-completes at ≥ 95% watched.
  Future<bool> reportProgress({
    required String videoResourceId,
    required String enrollmentId,
    required double currentTime,
    required bool completed,
  }) async {
    final body = await _api.post(_progress(videoResourceId), body: {
      'enrollment_id': enrollmentId,
      'current_time': currentTime,
      'completed': completed,
    });
    return body is Map && body['is_completed'] == true;
  }

  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  static String _str(Object? v) => v is String ? v : '';

  static MyCoursesPage mapPage(Object? body) {
    final rows = body is Map ? body['results'] : body;
    final last = body is Map ? body['last_watched_enrollment_id'] : null;
    return MyCoursesPage(
      lastWatchedEnrollmentId: last is String && last.isNotEmpty ? last : null,
      results: [
        if (rows is List)
          for (final r in rows)
            if (r is Map && _str(r['enrollment_id']).isNotEmpty)
              MyCourse(
                enrollmentId: _str(r['enrollment_id']),
                courseId: _str(r['course_id']),
                title: _str(r['course_title']),
                isMandatory: r['course_is_mandatory'] == true,
                thumbnailUrl: _str(r['course_thumbnail_url']).isNotEmpty
                    ? _str(r['course_thumbnail_url'])
                    : _str(r['course_pending_thumbnail_url']),
                completion:
                    _num(r['completion_percentage']).clamp(0, 100).toDouble(),
                status: _str(r['status']),
                deadline: parseApiDate(r['effective_deadline']),
              ),
      ],
    );
  }

  static MyCourseDetail mapDetail(Object? body) {
    final r = body is Map ? body : const {};
    final modules = r['modules'];
    return MyCourseDetail(
      enrollmentId: _str(r['enrollment_id']),
      courseId: _str(r['course_id']),
      title: _str(r['course_title']),
      isMandatory: r['course_is_mandatory'] == true,
      completion: _num(r['completion_percentage']).clamp(0, 100).toDouble(),
      status: _str(r['status']),
      modules: [
        if (modules is List)
          for (final m in modules)
            if (m is Map)
              MyCourseModule(
                moduleId: _str(m['module_id']),
                title: _str(m['title']),
                isLocked: m['is_locked'] == true,
                completedVideos: _num(m['completed_videos']).toInt(),
                totalVideos: _num(m['total_videos']).toInt(),
                videos: [
                  if (m['video_resources'] is List)
                    for (final v in m['video_resources'] as List)
                      if (v is Map)
                        MyCourseVideo(
                          videoResourceId: _str(v['video_resource_id']),
                          title: _str(v['title']),
                          durationSeconds: _num(v['duration_seconds']).round(),
                          hasVideo: _str(v['bunny_video_id']).isNotEmpty,
                          isUnlocked: v['is_unlocked'] == true,
                          isCompleted: v['progress'] is Map &&
                              (v['progress'] as Map)['is_completed'] == true,
                        ),
                ],
              ),
      ],
    );
  }

  static VideoView mapView(Object? body) {
    final r = body is Map ? body : const {};
    final res = r['resources'];
    return VideoView(
      videoResourceId: _str(r['video_resource_id']),
      title: _str(r['title']),
      videoUrl: _str(r['video_url']),
      lastPlayedPosition: _num(r['last_played_position']),
      isCompleted: r['is_completed'] == true,
      resources: [
        if (res is List)
          for (final x in res)
            if (x is Map && _str(x['file_url']).isNotEmpty)
              LessonResource(
                  title: _str(x['title']), fileUrl: _str(x['file_url'])),
      ],
    );
  }
}
