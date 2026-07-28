import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// A single lesson/module inside a [Course]. Mirrors the prototype's
/// `modules[]` seed records.
class CourseModule extends Equatable {
  final String id;
  final String title;
  final String dur; // display, e.g. "12 min"
  final bool video;
  final List<String> res; // resource file names (PDFs)

  const CourseModule({
    required this.id,
    required this.title,
    required this.dur,
    required this.video,
    required this.res,
  });

  CourseModule copyWith({String? title, bool? video, List<String>? res}) => CourseModule(
        id: id,
        title: title ?? this.title,
        dur: dur,
        video: video ?? this.video,
        res: res ?? this.res,
      );

  @override
  List<Object?> get props => [id, title, video, res];
}

/// An LMS course. Fields mirror the prototype's `LMS_COURSES` seed so the mock
/// data source maps directly and the shape is API-ready. Presentation-resolved
/// seed (icon glyph + tint/accent colours) is carried as typed values, resolved
/// once inside the data source.
class Course extends Equatable {
  final String id;
  final String title;
  final String sub;
  final String status; // 'published' | 'draft'
  final bool sequential;
  final bool mandatory;
  final String role; // "All Roles", "Sales rep", …
  final String deadline; // display, e.g. "20 Aug 2026"
  final String deadlineISO; // sortable/comparable, e.g. "2026-08-20"
  final String desc;
  final Color tint; // thumbnail background
  final Color accent; // icon / progress colour
  final IconData icon;
  final List<CourseModule> modules;

  const Course({
    required this.id,
    required this.title,
    required this.sub,
    required this.status,
    required this.sequential,
    required this.mandatory,
    required this.role,
    required this.deadline,
    required this.deadlineISO,
    required this.desc,
    required this.tint,
    required this.accent,
    required this.icon,
    required this.modules,
  });

  bool get isPublished => status == 'published';

  @override
  List<Object?> get props => [id];
}
