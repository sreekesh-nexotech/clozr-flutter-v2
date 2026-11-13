/// The learner side of the LMS ("My Trainings" and the lesson player), read
/// straight from `/lms/my-courses/` like the webapp — never joined with the
/// admin-only course list, which a learner cannot read.
library;

/// One of the signed-in user's published enrolments (a My Trainings card).
class MyCourse {
  const MyCourse({
    required this.enrollmentId,
    required this.courseId,
    required this.title,
    required this.isMandatory,
    required this.thumbnailUrl,
    required this.completion,
    required this.status,
    required this.deadline,
  });

  final String enrollmentId;
  final String courseId;
  final String title;
  final bool isMandatory;

  /// The saved thumbnail, else the pending one; empty when there is none.
  final String thumbnailUrl;

  /// 0–100.
  final double completion;

  /// `not_started` | `in_progress` | `completed` | `overdue`.
  final String status;
  final DateTime? deadline;

  bool get isCompleted => status == 'completed';
  bool get isOverdue => status == 'overdue';
}

/// `GET /lms/my-courses/` — the server orders it (overdue → soonest deadline
/// → no deadline → completed) and names the course last watched.
class MyCoursesPage {
  const MyCoursesPage({required this.results, this.lastWatchedEnrollmentId});

  final List<MyCourse> results;
  final String? lastWatchedEnrollmentId;
}

/// Watch progress on one video for this enrolment.
class MyCourseVideo {
  const MyCourseVideo({
    required this.videoResourceId,
    required this.title,
    required this.durationSeconds,
    required this.hasVideo,
    required this.isUnlocked,
    required this.isCompleted,
  });

  final String videoResourceId;
  final String title;
  final int durationSeconds;

  /// The server only sends a `bunny_video_id` for an unlocked, playable video.
  final bool hasVideo;
  final bool isUnlocked;
  final bool isCompleted;
}

class MyCourseModule {
  const MyCourseModule({
    required this.moduleId,
    required this.title,
    required this.isLocked,
    required this.completedVideos,
    required this.totalVideos,
    required this.videos,
  });

  final String moduleId;
  final String title;
  final bool isLocked;
  final int completedVideos;
  final int totalVideos;
  final List<MyCourseVideo> videos;
}

/// `GET /lms/my-courses/{enrollment_id}/` — the lesson player's course.
class MyCourseDetail {
  const MyCourseDetail({
    required this.enrollmentId,
    required this.courseId,
    required this.title,
    required this.isMandatory,
    required this.completion,
    required this.status,
    required this.modules,
  });

  final String enrollmentId;
  final String courseId;
  final String title;

  /// Not every payload carries it; the player also checks the block's list.
  final bool isMandatory;
  final double completion;
  final String status;
  final List<MyCourseModule> modules;

  List<MyCourseVideo> get videos => [for (final m in modules) ...m.videos];
}

/// A PDF attached to the lesson's module.
class LessonResource {
  const LessonResource({required this.title, required this.fileUrl});

  final String title;
  final String fileUrl;
}

/// `GET /lms/video-resources/{id}/view/?enrollment_id=` — what the player
/// embeds, and where to resume.
class VideoView {
  const VideoView({
    required this.videoResourceId,
    required this.title,
    required this.videoUrl,
    required this.lastPlayedPosition,
    required this.isCompleted,
    required this.resources,
  });

  final String videoResourceId;
  final String title;
  final String videoUrl;
  final double lastPlayedPosition;
  final bool isCompleted;
  final List<LessonResource> resources;
}
