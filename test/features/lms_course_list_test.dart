import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/training/domain/entities/course.dart';
import 'package:clozrapp/features/training/infrastructure/data_sources/remote/lms_remote_ds.dart';

Course _course(Map<String, dynamic> row) => LmsRemoteDataSource.mapCourse(
    {'course_id': 'c1', 'title': 'T', ...row}, 0)!;

void main() {
  test('Course builder subtitle: platform audience, else role names', () {
    expect(_course({'is_global': true, 'audience': 'admins'}).listSubtitle,
        'Provided by Clozr · admins only');
    expect(_course({'is_global': true, 'audience': 'users'}).listSubtitle,
        'Provided by Clozr · non-admin users');
    expect(_course({'is_global': true}).listSubtitle,
        'Provided by Clozr · everyone');
    expect(
        _course({
          'assigned_to_roles': [
            {'role_id': 'r1', 'name': 'CRM User'},
            {'role_id': 'r2', 'name': 'PMO User'},
          ],
        }).listSubtitle,
        'CRM User, PMO User');
    expect(_course({}).listSubtitle, '');
    // The server's "All users" pseudo-role is not a role name.
    final all = _course({
      'is_universal': true,
      'assigned_to_roles': [
        {'role_id': null, 'name': 'all'},
      ],
    });
    expect(all.roleNames, isEmpty);
    expect(all.listSubtitle, 'All users');
  });

  test('the course list carries the server counts', () {
    final c = _course({
      'modules_count': 2,
      'enrolled_users': [{}, {}, {}],
      'completion_percentage': 50.0,
      'is_global': true,
    });
    expect(c.moduleTotal, 2);
    expect(c.enrolledCount, 3);
    expect(c.completion, 50.0);
    expect(c.isGlobal, isTrue);
  });
}
