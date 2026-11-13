import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// A single Recent-Activity feed row. Mirrors the prototype's `LMS_ACTIVITY`
/// records (`{ dot, who, what, time }`).
class LmsActivity extends Equatable {
  final Color dot;
  final String who;
  final String what;
  final String time;

  /// The course the event is about (`course_title`), for the course detail's
  /// per-course feed. Empty when the row does not say.
  final String courseTitle;

  const LmsActivity({
    required this.dot,
    required this.who,
    required this.what,
    required this.time,
    this.courseTitle = '',
  });

  @override
  List<Object?> get props => [who, what, time];
}
