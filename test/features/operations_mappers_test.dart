import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/operations/infrastructure/data_sources/remote/ops_tasks_remote_ds.dart';
import 'package:clozrapp/features/operations/infrastructure/data_sources/remote/projects_remote_ds.dart';

void main() {
  setUp(UserDirectory.reset);
  tearDown(UserDirectory.reset);

  group('ProjectsRemoteDataSource.mapProject', () {
    Map<String, dynamic> slimRow() => {
          'project_id': 'a1b2c3d4-0000-0000-0000-000000000001',
          'naming_series': 'PRJ-1010',
          'project_name': 'Technopark Tejaswini — 4F office interiors',
          'is_archived': false,
          'status': 'f0e1d2c3-0000-0000-0000-0000000000aa',
          'status_name': 'Active',
          'project_type': '9a8b7c6d-0000-0000-0000-0000000000bb',
          'project_type_name': 'Implementation',
          'customer': '1122aabb-0000-0000-0000-0000000000cc',
          'customer_name': 'Technopark Tejaswini',
          'priority': 'High',
          'percent_complete': 75.0,
          'manager': '55ee66ff-0000-0000-0000-0000000000dd',
          'manager_name': 'Manoj Varma',
          'expected_start_date': '2026-01-05',
          'expected_end_date': '2026-06-28',
          'is_overdue': false,
          'created_at': '2026-07-01T10:00:00Z',
          'updated_at': '2026-07-20T08:30:00Z',
        };

    test('maps a slim row: uuid id (never naming_series), names, dates, defaults', () {
      final p = ProjectsRemoteDataSource.mapProject(slimRow())!;

      expect(p.id, 'a1b2c3d4-0000-0000-0000-000000000001');
      expect(p.name, 'Technopark Tejaswini — 4F office interiors');
      expect(p.type, 'Implementation');
      expect(p.company, 'Technopark Tejaswini');
      expect(p.internal, isFalse);
      expect(p.status, 'active');
      expect(p.pri, 'High');
      expect(p.progress, 75);
      expect(p.manager, '55ee66ff-0000-0000-0000-0000000000dd');
      expect(p.assignees, isEmpty);
      expect(p.myTask, isFalse);
      expect(p.start, '5 Jan 2026');
      expect(p.end, '28 Jun 2026');
      expect(p.endISO, '2026-06-28');
      expect(p.cost, ''); // estimated_costing absent on slim rows
      expect(p.visibility, 'Team');
      expect(p.method, 'Task-based');
      expect(p.desc, '');
    });

    test('null customer marks the project internal', () {
      final row = slimRow()
        ..['customer'] = null
        ..['customer_name'] = null;
      final p = ProjectsRemoteDataSource.mapProject(row)!;

      expect(p.internal, isTrue);
      expect(p.company, isNull);
    });

    test("the signed-in user's manager uuid maps to 'me'", () {
      UserDirectory.currentUserId = '55ee66ff-0000-0000-0000-0000000000dd';
      final p = ProjectsRemoteDataSource.mapProject(slimRow())!;
      expect(p.manager, 'me');
    });

    test('status names map onto the fixed UI keys', () {
      String statusOf(String? name) {
        final row = slimRow()..['status_name'] = name;
        return ProjectsRemoteDataSource.mapProject(row)!.status;
      }

      expect(statusOf('Planning'), 'planning');
      expect(statusOf('On Hold'), 'onhold');
      expect(statusOf('Completed'), 'completed');
      expect(statusOf('Cancelled'), 'cancelled');
      expect(statusOf(null), 'active'); // safe default
    });

    test('percent_complete tolerates numbers, decimal strings, nulls, out-of-range', () {
      int progressOf(Object? v) {
        final row = slimRow()..['percent_complete'] = v;
        return ProjectsRemoteDataSource.mapProject(row)!.progress;
      }

      expect(progressOf(75.0), 75);
      expect(progressOf('42.500000'), 43); // decimal string
      expect(progressOf(null), 0);
      expect(progressOf(250), 100); // clamped
      expect(progressOf(-5), 0); // clamped
    });

    test('a row without project_id is skipped (null)', () {
      expect(ProjectsRemoteDataSource.mapProject({'project_name': 'Ghost'}), isNull);
      expect(ProjectsRemoteDataSource.mapProject({'project_id': ''}), isNull);
    });

    test('a minimal row survives with defaults (null tolerance)', () {
      final p = ProjectsRemoteDataSource.mapProject({'project_id': 'x'})!;

      expect(p.id, 'x');
      expect(p.name, '');
      expect(p.type, '');
      expect(p.internal, isTrue); // no customer key ⇒ internal
      expect(p.pri, 'Medium');
      expect(p.progress, 0);
      expect(p.manager, '');
      expect(p.start, '');
      expect(p.end, '');
      expect(p.endISO, '');
    });
  });

  group('OpsTasksRemoteDataSource.mapOpsTask', () {
    Map<String, dynamic> slimRow() => {
          'task_id': '5cbf187a-0000-0000-0000-000000000001',
          'subject': 'Snag list & handover',
          'project': '0e1b9270-0000-0000-0000-000000000002',
          'project_name': 'Technopark Tejaswini — 4F office interiors',
          'task_group': '7f39d91e-0000-0000-0000-000000000003',
          'task_group_name': 'Site Work',
          'type': 'fb59b033-0000-0000-0000-000000000004',
          'task_type_name': 'Installation',
          'status': 'acb8c200-0000-0000-0000-000000000005',
          'status_name': 'Pending Review',
          'priority': 'Urgent',
          'is_milestone': true,
          'pending_dependency_count': 1,
          'is_overdue': false,
          'progress': '0.000000',
          'computed_progress': 39.0,
          'assigned_to': {'user_id': 'f126141c-0000-0000-0000-000000000006', 'full_name': 'Manoj Varma'},
          'assignees': [
            {'user_id': 'f126141c-0000-0000-0000-000000000006', 'first_name': 'Manoj', 'last_name': 'Varma'},
          ],
          'exp_end_date': '2026-06-30T17:30:00',
        };

    test('maps a slim row: uuid ids, group, status, priority, end date/time', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow())!;

      expect(t.id, '5cbf187a-0000-0000-0000-000000000001');
      expect(t.subject, 'Snag list & handover');
      expect(t.projId, '0e1b9270-0000-0000-0000-000000000002'); // project uuid = Project.id
      expect(t.group, 'Site Work');
      expect(t.status, 'review');
      expect(t.pri, 'Urgent');
      expect(t.assignees, ['f126141c-0000-0000-0000-000000000006']);
      expect(t.milestone, isTrue);
      expect(t.start, '');
      expect(t.startTime, '');
      expect(t.end, '30 Jun 2026');
      expect(t.endTime, '5:30 PM');
      expect(t.endISO, '2026-06-30T17:30:00');
      expect(t.expHrs, 0);
      expect(t.progress, 39); // computed_progress wins over the '0.000000' string
      expect(t.weight, 1);
      expect(t.dept, '');
      expect(t.color.name, '');
      expect(t.subtasks, isEmpty);
      expect(t.waitingOn, isEmpty); // slim rows expose pending_dependency_count only
      expect(t.notes, isEmpty);
      expect(t.actualStart, isNull);
      expect(t.actualEnd, isNull);
      expect(t.fromTicket, isNull);
    });

    test('progress falls back to the decimal string when computed_progress is absent', () {
      final row = slimRow()
        ..remove('computed_progress')
        ..['progress'] = '62.500000';
      expect(OpsTasksRemoteDataSource.mapOpsTask(row)!.progress, 63);
    });

    test("assignee uuids route through UserDirectory (signed-in user becomes 'me')", () {
      UserDirectory.currentUserId = 'f126141c-0000-0000-0000-000000000006';
      final row = slimRow()
        ..['assignees'] = [
          {'user_id': 'f126141c-0000-0000-0000-000000000006', 'first_name': 'Manoj', 'last_name': 'Varma'},
          {'user_id': 'other-uuid', 'first_name': 'Sneha', 'last_name': 'Thomas'},
        ];
      expect(OpsTasksRemoteDataSource.mapOpsTask(row)!.assignees, ['me', 'other-uuid']);
    });

    test('status/priority/group fall back safely when absent', () {
      final row = slimRow()
        ..['status_name'] = null
        ..['priority'] = null
        ..['task_group_name'] = null;
      final t = OpsTasksRemoteDataSource.mapOpsTask(row)!;

      expect(t.status, 'open');
      expect(t.pri, 'Medium');
      expect(t.group, 'No group');
    });

    test("status name 'Working' maps to the working key", () {
      final row = slimRow()..['status_name'] = 'Working';
      expect(OpsTasksRemoteDataSource.mapOpsTask(row)!.status, 'working');
    });

    test('a date-only exp_end_date leaves endTime empty', () {
      final row = slimRow()..['exp_end_date'] = '2026-05-20';
      final t = OpsTasksRemoteDataSource.mapOpsTask(row)!;

      expect(t.end, '20 May 2026');
      expect(t.endTime, '');
      expect(t.endISO, '2026-05-20');
    });

    test('a row without task_id is skipped (null)', () {
      expect(OpsTasksRemoteDataSource.mapOpsTask({'subject': 'Ghost'}), isNull);
      expect(OpsTasksRemoteDataSource.mapOpsTask({'task_id': ''}), isNull);
    });

    test('a minimal row survives with defaults (null tolerance)', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask({'task_id': 'x'})!;

      expect(t.id, 'x');
      expect(t.subject, '');
      expect(t.projId, '');
      expect(t.group, 'No group');
      expect(t.status, 'open');
      expect(t.pri, 'Medium');
      expect(t.assignees, isEmpty);
      expect(t.milestone, isFalse);
      expect(t.end, '');
      expect(t.endTime, '');
      expect(t.endISO, '');
      expect(t.progress, 0);
      expect(t.desc, '');
    });
  });
}
