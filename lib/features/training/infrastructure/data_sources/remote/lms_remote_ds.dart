import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../../../data/mock/mock_users.dart';
import '../../../domain/entities/course.dart';
import '../../../domain/entities/learner_record.dart';
import '../../../domain/entities/lms_activity.dart';
import '../local/lms_people.dart';

/// Remote LMS data: HTTP via [ApiService] + JSON→entity mapping. No caching
/// here — and none in the repository either (LMS/rewards intentionally skip
/// the Hive fallback; there is no dedicated cache box for them).
///
/// Mappers are static so tests can feed fixture maps without any HTTP stack.
class LmsRemoteDataSource {
  LmsRemoteDataSource(this._api);

  final ApiService _api;

  /// LMS routes not yet in `ApiEndpoints` (core is out of scope for this
  /// slice); kept here until the constants file is next touched.
  static const String _courses = '/lms/courses/';
  static const String _learners = '/lms/learners/';
  static const String _recentActivity = '/lms/dashboard/recent-activity/';
  static String _videoProgress(String videoResourceId) =>
      '/lms/video-resources/$videoResourceId/progress/';

  static const int _maxPages = 3;

  /// `course_id → modules_count` from the last course fetch — used to expand
  /// an enrollment's overall percentage into per-module values.
  final Map<String, int> moduleCountByCourse = {};

  /// `course_id → enrollment_id` from the last my-courses fetch — needed by
  /// the progress write (the API keys progress on the enrollment).
  final Map<String, String> _enrollmentByCourse = {};

  // ── Courses ──

  /// GET /lms/courses/ (paginated, bounded). The LIST payload carries
  /// `modules_count` but NO embedded modules (confirmed against
  /// `CourseListSerializer`), so mapped courses have `modules: const []` —
  /// fetching each course's modules here would be an N+1.
  Future<List<Course>> fetchCourses() async {
    final rows = <Map<String, dynamic>>[];
    int? page;
    for (var i = 0; i < _maxPages; i++) {
      final body = await _api.get(_courses, query: {
        'page_size': ApiConfig.defaultPageSize,
        if (page != null) 'page': page,
      });
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (row) => row);
      rows.addAll(paged.results);
      page = pageOf(paged.next);
      if (page == null) break;
    }
    moduleCountByCourse
      ..clear()
      ..addAll({
        for (final row in rows)
          if (row['course_id'] is String)
            row['course_id'] as String: (row['modules_count'] as num?)?.toInt() ?? 0,
      });
    return mapCourseRows(rows);
  }

  // ── My record ('me') ──

  /// GET /lms/my-courses/ → the signed-in user's [LearnerRecord].
  /// [moduleCountByCourse] (from [fetchCourses]) expands each enrollment's
  /// overall percentage across the course's module count.
  Future<LearnerRecord> fetchMyRecord() async {
    final body = await _api.get(ApiEndpoints.myCourses);
    final rows = body is Map<String, dynamic> ? body['results'] : body;
    final courses = <CourseProgress>[];
    _enrollmentByCourse.clear();
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final entry = mapEnrollmentRow(
          row,
          moduleCount: moduleCountByCourse[row['course_id']] ?? 0,
        );
        if (entry == null) continue;
        courses.add(entry);
        final enrollmentId = row['enrollment_id'] as String? ?? '';
        if (enrollmentId.isNotEmpty) {
          _enrollmentByCourse[entry.courseId] = enrollmentId;
        }
      }
    }
    // Refresh the LMS identity for 'me' from the session roster so the
    // learner surfaces show the real signed-in name.
    final self = MockUsers.of('me');
    LmsPeople.register(
      rid: 'me',
      name: self.name,
      role: self.role.replaceAll(RegExp(r'\s*·\s*You$'), ''),
    );
    return LearnerRecord(rid: 'me', courses: courses);
  }

  // ── Other learners (admin-only endpoint; repo handles the 403) ──

  /// GET /lms/learners/ → aggregate records for the rest of the org.
  Future<List<LearnerRecord>> fetchLearnerRecords() async {
    final body = await _api.get(_learners);
    final rows = body is Map<String, dynamic> ? body['results'] : body;
    final out = <LearnerRecord>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final rec = mapLearnerRow(row);
        if (rec != null) out.add(rec);
      }
    }
    return out;
  }

  // ── Activity feed (admin-only endpoint; repo handles the 403) ──

  /// GET /lms/dashboard/recent-activity/.
  Future<List<LmsActivity>> fetchActivity() async {
    final body = await _api.get(_recentActivity, query: {'limit': 50});
    final rows = body is Map<String, dynamic> ? body['results'] : body;
    final out = <LmsActivity>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final activity = mapActivityRow(row);
        if (activity != null) out.add(activity);
      }
    }
    return out;
  }

  // ── Progress write ──

  /// Persists module progress for the signed-in user. The API tracks progress
  /// per VIDEO on an ENROLLMENT (`POST /lms/video-resources/{id}/progress/`),
  /// so this resolves course → enrollment (from the my-courses fetch), then
  /// enrollment detail → the module's videos, and posts:
  /// - value ≥ 100 → `completed: true` for every video in the module;
  /// - value < 100 → a watch-position ping on the first video (in-progress).
  Future<void> postModuleProgress({
    required String courseId,
    required String moduleId,
    required int index,
    required int value,
  }) async {
    var enrollmentId = _enrollmentByCourse[courseId];
    if (enrollmentId == null) {
      await fetchMyRecord(); // Cold start — rebuild the course→enrollment map.
      enrollmentId = _enrollmentByCourse[courseId];
    }
    if (enrollmentId == null) return;

    final detail = await _api.get(ApiEndpoints.myCourse(enrollmentId));
    if (detail is! Map<String, dynamic>) return;
    final modules = detail['modules'];
    if (modules is! List) return;

    // Prefer the module UUID; fall back to the course-position index (list
    // payloads carry no module ids, so the notifier often passes '').
    Map<String, dynamic>? module;
    for (final m in modules) {
      if (m is Map<String, dynamic> && m['module_id'] == moduleId && moduleId.isNotEmpty) {
        module = m;
        break;
      }
    }
    if (module == null && index >= 0 && index < modules.length) {
      final m = modules[index];
      if (m is Map<String, dynamic>) module = m;
    }
    if (module == null) return;

    final videos = module['video_resources'];
    if (videos is! List) return;
    final videoIds = [
      for (final v in videos)
        if (v is Map && v['video_resource_id'] is String) v['video_resource_id'] as String,
    ];
    if (videoIds.isEmpty) return;

    if (value >= 100) {
      for (final id in videoIds) {
        await _api.post(_videoProgress(id), body: {
          'enrollment_id': enrollmentId,
          'current_time': 0,
          'completed': true,
        });
      }
    } else {
      await _api.post(_videoProgress(videoIds.first), body: {
        'enrollment_id': enrollmentId,
        'current_time': 1,
        'completed': false,
      });
    }
  }

  /// Extracts the page number from a DRF `next` URL (absolute or relative).
  static int? pageOf(String? next) {
    if (next == null || next.isEmpty) return null;
    final uri = Uri.tryParse(next);
    if (uri == null) return null;
    return int.tryParse(uri.queryParameters['page'] ?? '');
  }

  // ── Mapping (visible for tests) ──

  /// The mock seed's tint/accent/icon combos, cycled deterministically by list
  /// index so course thumbnails stay stable across refetches.
  static const List<(Color, Color, IconData)> visualCycle = [
    (AppColors.blueSubtle, AppColors.blueBright, PhosphorIconsFill.usersThree),
    (AppColors.tintGreen, AppColors.success, PhosphorIconsFill.trendUp),
    (AppColors.tintAmber, AppColors.warningDeep, PhosphorIconsFill.briefcase),
    (Color(0xFFF3E8FA), AppColors.pending, PhosphorIconsFill.shieldCheck),
    (AppColors.tintRed, AppColors.error, PhosphorIconsFill.headset),
    (AppColors.tintNavy, AppColors.navy, PhosphorIconsFill.hardHat),
  ];

  /// Maps a raw results list defensively: non-map entries and rows without a
  /// `course_id` are skipped, never fatal.
  static List<Course> mapCourseRows(List<dynamic> rows) {
    final out = <Course>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final course = mapCourse(row, out.length);
      if (course != null) out.add(course);
    }
    return out;
  }

  /// Maps one API course row (list or detail shape) onto the UI entity.
  /// [index] drives the deterministic visual cycle. Returns null when the row
  /// has no `course_id`.
  static Course? mapCourse(Map<String, dynamic> row, int index) {
    final id = row['course_id'] as String? ?? '';
    if (id.isEmpty) return null;

    final desc = row['description'] as String? ?? '';
    final deadlineDate = parseApiDate(row['deadline']);
    final visual = visualCycle[index % visualCycle.length];

    return Course(
      id: id,
      title: row['title'] as String? ?? '',
      sub: desc.isEmpty ? '' : desc.split('\n').first.trim(),
      status: (row['status'] as String? ?? '') == 'published' || row['is_published'] == true
          ? 'published'
          : 'draft',
      sequential: row['is_sequential'] as bool? ?? false,
      mandatory: row['is_mandatory'] as bool? ?? false,
      role: _roleLabel(row),
      deadline: absoluteDate(deadlineDate),
      // `deadlineISO` must stay date-only sortable ("2026-08-20") — LmsLogic
      // appends "T23:59:59" before parsing, so a full ISO timestamp would blow
      // up the status resolver.
      deadlineISO: deadlineDate == null
          ? ''
          : deadlineDate.toIso8601String().substring(0, 10),
      desc: desc,
      tint: visual.$1,
      accent: visual.$2,
      icon: visual.$3,
      modules: _mapModules(row['modules']),
    );
  }

  /// Assigned-role display: universal ("all") or first role name → the mock's
  /// "All Roles" default when absent.
  static String _roleLabel(Map<String, dynamic> row) {
    if (row['is_universal'] == true) return 'All Roles';
    final roles = row['assigned_to_roles'];
    if (roles is List) {
      for (final r in roles) {
        if (r is! Map) continue;
        final name = r['name'] as String? ?? '';
        if (name.isEmpty) continue;
        return name == 'all' ? 'All Roles' : name;
      }
    }
    return 'All Roles';
  }

  /// Embedded modules exist only on DETAIL payloads; list rows map to `[]`.
  static List<CourseModule> _mapModules(Object? modules) {
    if (modules is! List) return const [];
    final out = <CourseModule>[];
    for (final m in modules) {
      if (m is! Map<String, dynamic>) continue;
      final id = m['module_id'] as String? ?? '';
      if (id.isEmpty) continue;
      final videos = m['video_resources'];
      var seconds = 0;
      var hasVideo = false;
      if (videos is List) {
        for (final v in videos) {
          if (v is! Map) continue;
          hasVideo = true;
          seconds += (v['duration_seconds'] as num?)?.toInt() ?? 0;
        }
      }
      final resources = m['resources'];
      out.add(CourseModule(
        id: id,
        title: m['title'] as String? ?? '',
        dur: seconds > 0 ? '${(seconds / 60).ceil()} min' : '',
        video: hasVideo,
        res: [
          if (resources is List)
            for (final r in resources)
              if (r is Map && r['title'] is String) r['title'] as String,
        ],
      ));
    }
    return out;
  }

  /// Maps one /lms/my-courses/ enrollment row onto a [CourseProgress].
  /// The list payload has no per-module ints, so the overall
  /// `completion_percentage` is replicated across [moduleCount] modules
  /// (or kept as a single overall value when the count is unknown).
  static CourseProgress? mapEnrollmentRow(Map<String, dynamic> row, {int moduleCount = 0}) {
    final courseId = row['course_id'] as String? ?? '';
    if (courseId.isEmpty) return null;
    final pct = ((row['completion_percentage'] as num?)?.round() ?? 0).clamp(0, 100);
    return CourseProgress(
      courseId: courseId,
      mods: List<int>.filled(moduleCount > 0 ? moduleCount : 1, pct),
    );
  }

  /// Maps one /lms/learners/ row onto an aggregate [LearnerRecord]. The row
  /// carries counts + an overall percentage but no course ids, so synthetic
  /// per-course entries reproduce the aggregate: `completed_courses` × [100]
  /// plus the remainder at the overall percentage (0 when not started). The
  /// synthetic course ids are unknown to the course lookup, so detail rows
  /// hide themselves while counts/status still read correctly. Rows for the
  /// signed-in user (covered by /lms/my-courses/) return null.
  static LearnerRecord? mapLearnerRow(Map<String, dynamic> row) {
    final userId = row['user_id'] as String? ?? '';
    if (userId.isEmpty) return null;
    final rid = UserDirectory.mapUserId(userId);
    if (rid == 'me') return null;

    final name = row['name'] as String? ?? '';
    final role = row['role'];
    final roleName = role is Map ? (role['name'] as String? ?? '') : '';
    LmsPeople.register(rid: rid, name: name, role: roleName);
    UserDirectory.register(userId: userId, fullName: name, role: roleName);

    final assigned = (row['assigned_courses'] as num?)?.toInt() ?? 0;
    final completed = ((row['completed_courses'] as num?)?.toInt() ?? 0).clamp(0, assigned);
    final overall = ((row['overall_progress_percentage'] as num?)?.round() ?? 0).clamp(0, 99);
    final started = (row['status'] as String? ?? '') != 'not_started';
    return LearnerRecord(rid: rid, courses: [
      for (var i = 0; i < assigned; i++)
        CourseProgress(
          courseId: 'agg-$i',
          mods: [if (i < completed) 100 else if (started) (overall > 0 ? overall : 1) else 0],
        ),
    ]);
  }

  /// Maps one recent-activity row. Server colours (green/yellow/red/violet)
  /// map onto the mock palette; unknown → the neutral blue.
  static LmsActivity? mapActivityRow(Map<String, dynamic> row) {
    final who = row['user_name'] as String? ?? '';
    final description = row['description'] as String? ?? '';
    final action = row['action'] as String? ?? '';
    final courseTitle = row['course_title'] as String? ?? '';
    final what = description.isNotEmpty
        ? description
        : [action.replaceAll('_', ' '), courseTitle].where((s) => s.isNotEmpty).join(' ');
    if (who.isEmpty && what.isEmpty) return null;
    return LmsActivity(
      dot: switch (row['color'] as String? ?? '') {
        'green' => AppColors.success,
        'yellow' => AppColors.warning,
        'red' => AppColors.error,
        'violet' => AppColors.pending,
        _ => AppColors.blueBright,
      },
      who: who,
      what: what,
      time: relativeTime(parseApiDate(row['created_at'])),
    );
  }
}
