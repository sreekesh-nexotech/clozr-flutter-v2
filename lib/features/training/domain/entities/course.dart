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

  /// The first lesson video's title (course detail payloads only).
  final String videoTitle;

  const CourseModule({
    required this.id,
    required this.title,
    required this.dur,
    required this.video,
    required this.res,
    this.videoTitle = '',
  });

  CourseModule copyWith({String? title, bool? video, List<String>? res}) =>
      CourseModule(
        id: id,
        title: title ?? this.title,
        dur: dur,
        video: video ?? this.video,
        res: res ?? this.res,
        videoTitle: videoTitle,
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

  /// Server figures from the course LIST (`GET /lms/courses/`), which carries
  /// no embedded modules. Null when the source does not send them (the mock
  /// seed), in which case the counts are derived from [modules] / records.
  final int? modulesCount;
  final int? enrolledCount;

  /// Average completion across the course's learners, 0–100.
  final double? completion;

  /// A platform (Clozr) course: read-only for tenants — never edited, always
  /// opened on its detail.
  final bool isGlobal;

  /// The role names it is assigned to (`all` for everyone), webapp
  /// `courseRoleNames` — the course table's subtitle and its role filter.
  final List<String> roleNames;

  /// Who a platform course is for: `all` | `admins` | `users` (webapp
  /// `CourseAudience`). Empty when the source does not say.
  final String audience;

  /// Assigned to every user (`is_universal`).
  final bool isUniversal;

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
    this.modulesCount,
    this.enrolledCount,
    this.completion,
    this.isGlobal = false,
    this.roleNames = const [],
    this.audience = '',
    this.isUniversal = false,
  });

  /// Webapp `courseSubtitle` (Course builder list): a platform course reads
  /// "Provided by Clozr · <audience>"; a tenant course its role names.
  String get listSubtitle {
    if (isGlobal) {
      final who = switch (audience) {
        'admins' => 'admins only',
        'users' => 'non-admin users',
        _ => 'everyone',
      };
      return 'Provided by Clozr · $who';
    }
    if (roleNames.isEmpty && isUniversal) return 'All users';
    return roleNames.join(', ');
  }

  /// Modules on the course: the server count when known, else the embedded list.
  int get moduleTotal => modulesCount ?? modules.length;

  bool get isPublished => status == 'published';

  @override
  List<Object?> get props => [id];
}
