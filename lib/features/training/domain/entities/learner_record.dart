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

  const LearnerRecord({required this.rid, required this.courses});

  LearnerRecord copyWith({List<CourseProgress>? courses}) =>
      LearnerRecord(rid: rid, courses: courses ?? this.courses);

  CourseProgress? entryFor(String courseId) {
    for (final c in courses) {
      if (c.courseId == courseId) return c;
    }
    return null;
  }

  @override
  List<Object?> get props => [rid, courses];
}
