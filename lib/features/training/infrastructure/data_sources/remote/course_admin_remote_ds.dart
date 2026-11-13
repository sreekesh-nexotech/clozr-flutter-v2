import '../../../../../core/network/api_service.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/course.dart';
import '../local/lms_people.dart';
import 'lms_remote_ds.dart';

/// One learner on one course — a row of the course detail's "Assigned
/// learners" (`GET /lms/learners/?course_id=`), with the server's own status.
class CourseLearnerRow {
  const CourseLearnerRow({
    required this.userId,
    required this.rid,
    required this.name,
    required this.roleName,
    required this.pct,
    required this.status,
  });

  final String userId;

  /// The app's roster id for the learner detail route (`me` for yourself).
  final String rid;
  final String name;
  final String roleName;
  final int pct;

  /// `completed` | `inprogress` | `overdue` | `notstarted` (the LMS status keys).
  final String status;
}

/// One row of the org-wide Learners table (`GET /lms/learners/`): a user's
/// aggregate across every course they are enrolled on, as the server derives it.
class LearnerSummary {
  const LearnerSummary({
    required this.userId,
    required this.rid,
    required this.name,
    required this.email,
    required this.roleName,
    required this.assigned,
    required this.completed,
    required this.pct,
    required this.status,
    required this.deadline,
  });

  final String userId;

  /// The app's roster id (`me` for yourself) — for the avatar colour.
  final String rid;
  final String name;
  final String email;
  final String roleName;
  final int assigned;
  final int completed;
  final int pct;

  /// `completed` | `inprogress` | `overdue` | `notstarted`.
  final String status;

  /// The server's pick: nearest overdue deadline, else nearest upcoming.
  final DateTime? deadline;

  bool get overdue => status == 'overdue';
}

/// An org user offered in the Assign course sheet.
class AssignableUser {
  const AssignableUser(
      {required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final String role;
}

/// The course-management reads and writes behind the course detail, as the
/// webapp makes them (course detail, per-course learners, assign).
class CourseAdminRemoteDataSource {
  CourseAdminRemoteDataSource(this._api);

  final ApiService _api;

  /// `GET /lms/courses/{id}/` — the DETAIL payload with embedded modules,
  /// videos and resources. A deleted course answers 404.
  Future<Course?> fetchCourse(String id) async {
    final body = await _api.get('/lms/courses/$id/');
    return body is Map<String, dynamic>
        ? LmsRemoteDataSource.mapCourse(body, 0)
        : null;
  }

  Future<List<CourseLearnerRow>> fetchLearners(String courseId) async {
    final body =
        await _api.get('/lms/learners/', query: {'course_id': courseId});
    final rows = body is Map ? body['results'] : body;
    return [
      if (rows is List)
        for (final r in rows)
          if (r is Map && r['user_id'] is String)
            mapLearner(Map<String, dynamic>.from(r)),
    ];
  }

  /// `GET /lms/learners/` — every user with at least one enrolment.
  Future<List<LearnerSummary>> fetchAllLearners() async {
    final body = await _api.get('/lms/learners/');
    final rows = body is Map ? body['results'] : body;
    return [
      if (rows is List)
        for (final r in rows)
          if (r is Map && r['user_id'] is String)
            mapSummary(Map<String, dynamic>.from(r)),
    ];
  }

  static LearnerSummary mapSummary(Map<String, dynamic> r) {
    final row = mapLearner(r);
    int n(Object? v) => v is num ? v.toInt() : 0;
    return LearnerSummary(
      userId: row.userId,
      rid: row.rid,
      name: row.name,
      email: '${r['email'] ?? ''}'.trim(),
      roleName: row.roleName,
      assigned: n(r['assigned_courses']),
      completed: n(r['completed_courses']),
      pct: row.pct,
      status: row.status,
      deadline: r['deadline'] is String
          ? DateTime.tryParse(r['deadline'] as String)
          : null,
    );
  }

  /// `POST /lms/learners/{id}/nudge/` — without [courseId] the server reminds
  /// the learner about all of their unfinished courses (webapp list / detail).
  Future<void> nudge(String userId, {String? courseId}) =>
      _api.post('/lms/learners/$userId/nudge/',
          body: {if (courseId != null) 'course_id': courseId});

  static CourseLearnerRow mapLearner(Map<String, dynamic> r) {
    final userId = r['user_id'] as String;
    final name = r['name'] as String? ?? '';
    final role = r['role'];
    final roleName = role is Map ? (role['name'] as String? ?? '') : '';
    final rid = UserDirectory.mapUserId(userId);
    LmsPeople.register(rid: rid, name: name, role: roleName);
    UserDirectory.register(userId: userId, fullName: name, role: roleName);
    return CourseLearnerRow(
      userId: userId,
      rid: rid,
      name: name,
      roleName: roleName,
      pct: ((r['overall_progress_percentage'] as num?) ?? 0)
          .round()
          .clamp(0, 100),
      status: switch (r['status']) {
        'completed' => 'completed',
        'overdue' => 'overdue',
        'in_progress' => 'inprogress',
        _ => 'notstarted',
      },
    );
  }

  /// `GET /management/users/` — everyone in the org (webapp assignable users).
  Future<List<AssignableUser>> fetchUsers() async {
    final body =
        await _api.getAllPages('/management/users/', query: {'page_size': 200});
    final rows = body is Map ? body['results'] : body;
    return [
      if (rows is List)
        for (final r in rows)
          if (r is Map && r['user_id'] is String)
            AssignableUser(
              id: r['user_id'] as String,
              name: _name(r),
              role: r['roles'] is List &&
                      (r['roles'] as List).isNotEmpty &&
                      (r['roles'] as List).first is Map
                  ? '${((r['roles'] as List).first as Map)['name'] ?? ''}'
                  : '',
            ),
    ];
  }

  static String _name(Map r) {
    final full = '${r['full_name'] ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    final parts = ['${r['first_name'] ?? ''}', '${r['last_name'] ?? ''}']
        .where((s) => s.trim().isNotEmpty)
        .join(' ');
    if (parts.isNotEmpty) return parts;
    return '${r['username'] ?? r['email'] ?? '—'}';
  }

  /// `POST /lms/learners/assign/ {course_id, user_ids, deadline?}` → how many
  /// were newly enrolled.
  Future<int> assign(
      {required String courseId,
      required List<String> userIds,
      DateTime? deadline}) async {
    final d = deadline;
    final body = await _api.post('/lms/learners/assign/', body: {
      'course_id': courseId,
      'user_ids': userIds,
      if (d != null)
        'deadline':
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00Z',
    });
    final n = body is Map ? body['enrolled'] : null;
    return n is num ? n.toInt() : userIds.length;
  }
}
