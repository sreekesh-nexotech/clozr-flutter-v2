import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/training/infrastructure/data_sources/remote/course_admin_remote_ds.dart';

void main() {
  test('Learners row maps the server aggregate as the webapp reads it', () {
    final l = CourseAdminRemoteDataSource.mapSummary({
      'user_id': '29730397-7743-4ea7-823d-cf94e2d7701e',
      'name': 'Sufail Salim',
      'email': 'sufail.salim@nexotech.cc',
      'role': {'role_id': 'r1', 'name': 'CRM User'},
      'assigned_courses': 2,
      'completed_courses': 0,
      'overall_progress_percentage': 0.4,
      'status': 'overdue',
      'deadline': '2026-10-20T00:00:00Z',
    });
    expect(l.name, 'Sufail Salim');
    expect(l.email, 'sufail.salim@nexotech.cc');
    expect(l.roleName, 'CRM User');
    expect((l.assigned, l.completed, l.pct), (2, 0, 0));
    expect(l.status, 'overdue');
    expect(l.overdue, isTrue);
    expect(l.deadline, DateTime.utc(2026, 10, 20));
  });

  test('Missing fields fall back to webapp defaults', () {
    final l = CourseAdminRemoteDataSource.mapSummary({
      'user_id': 'cadc69f1-aed0-4584-848f-1095751b349c',
      'name': 'Neeraja Pradeep',
      'role': null,
      'status': 'in_progress',
      'deadline': null,
    });
    expect(l.email, '');
    expect(l.roleName, '');
    expect((l.assigned, l.completed, l.pct), (0, 0, 0));
    expect(l.status, 'inprogress');
    expect(l.deadline, isNull);
  });
}
