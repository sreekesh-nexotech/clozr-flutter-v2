import 'package:equatable/equatable.dart';

/// One learner's progress on one course — the per-module completion
/// percentages. Mirrors the prototype's `{ c, mods }` entry.
class CourseProgress extends Equatable {
  final String courseId; // the prototype's `c`
  final List<int> mods; // per-module percentages, 0–100

  const CourseProgress({required this.courseId, required this.mods});

  CourseProgress copyWith({List<int>? mods}) =>
      CourseProgress(courseId: courseId, mods: mods ?? this.mods);

  @override
  List<Object?> get props => [courseId, mods];
}

/// A learner's full training record — every course they're enrolled in.
/// Mirrors the prototype's `LMS_RECS[]` entry (`{ rid, courses }`).
class LearnerRecord extends Equatable {
  final String rid; // user id, e.g. 'me', 'an'
  final List<CourseProgress> courses;

  /// The server's own verdict on this learner (`not_started` / `in_progress` /
  /// `completed` / `overdue`), when the row carried one. Null for records
  /// built locally (mock seed, the signed-in user's per-module record), where
  /// [LmsLogic.aggStatus] derives it from the courses instead.
  ///
  /// Needed because `/lms/learners/` returns only aggregate counts, so the
  /// courses here carry synthetic ids with no deadline to judge against — the
  /// derived status could say "in progress" for a learner the server had
  /// already marked overdue.
  final String? serverStatus;

  const LearnerRecord({
    required this.rid,
    required this.courses,
    this.serverStatus,
  });

  LearnerRecord copyWith({List<CourseProgress>? courses}) =>
      LearnerRecord(
          rid: rid, courses: courses ?? this.courses, serverStatus: serverStatus);

  CourseProgress? entryFor(String courseId) {
    for (final c in courses) {
      if (c.courseId == courseId) return c;
    }
    return null;
  }

  @override
  List<Object?> get props => [rid, courses];
}
