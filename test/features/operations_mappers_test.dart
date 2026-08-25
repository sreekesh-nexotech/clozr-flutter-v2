import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/domain/entities/audit_entry.dart';
import 'package:clozrapp/features/operations/infrastructure/data_sources/remote/ops_tasks_remote_ds.dart';
import 'package:clozrapp/features/operations/domain/entities/ops_task.dart';
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
      // The detail-only fields stay empty on a slim row rather than being
      // guessed. They used to read "Team" and "Task-based" whatever the
      // project actually was, because `?view=list` never sends them.
      expect(p.cost, '');
      expect(p.visibility, '');
      expect(p.method, '');
      expect(p.team, '');
      expect(p.assignees, isEmpty);
      expect(p.desc, '');
    });

    test('the full row fills the fields the slim row drops', () {
      final p = ProjectsRemoteDataSource.mapProject(slimRow()
        ..['estimated_costing'] = '2500000.000000'
        ..['visibility'] = 'organization'
        ..['percent_complete_method'] = 'Task Weight'
        ..['assigned_team_name'] = 'Team North'
        ..['assignees'] = [
          {'user_id': 'u-1', 'first_name': 'Asha', 'last_name': 'Rao'},
          {'user_id': 'u-2', 'first_name': 'Vinod', 'last_name': 'K'},
        ])!;

      expect(p.cost, '₹25L');
      // The raw amount travels alongside the display string — "₹25L" stripped
      // to its digits is 25, so the edit form must prefill from this.
      expect(p.costNum, 2500000);
      // The wire value is a lowercase enum; the panel shows it capitalised.
      expect(p.visibility, 'Organization');
      expect(p.method, 'Task Weight');
      expect(p.team, 'Team North');
      expect(p.assignees, ['u-1', 'u-2']);
    });

    test('naming_series is the code to show; id stays the UUID', () {
      final p = ProjectsRemoteDataSource.mapProject(slimRow())!;

      // The card printed `p.id` — a raw UUID — where the code belongs.
      expect(p.code, 'PRJ-1010');
      expect(p.id, 'a1b2c3d4-0000-0000-0000-000000000001');
    });

    test('is_overdue comes from the server, not the frozen prototype clock', () {
      expect(ProjectsRemoteDataSource.mapProject(slimRow())!.isOverdue, isFalse);
      expect(
        ProjectsRemoteDataSource.mapProject(slimRow()..['is_overdue'] = true)!.isOverdue,
        isTrue,
      );
      // Absent stays null so the caller keeps its date fallback rather than
      // reading a missing flag as "not overdue".
      expect(
        ProjectsRemoteDataSource.mapProject(slimRow()..remove('is_overdue'))!.isOverdue,
        isNull,
      );
    });

    test('is_archived is carried, so the menu can offer Restore', () {
      expect(ProjectsRemoteDataSource.mapProject(slimRow())!.isArchived, isFalse);
      expect(
        ProjectsRemoteDataSource.mapProject(slimRow()..['is_archived'] = true)!
            .isArchived,
        isTrue,
      );
    });

    test('an unset budget stays blank — an absent cost is not ₹0', () {
      final p = ProjectsRemoteDataSource.mapProject(
          slimRow()..['estimated_costing'] = '0.000000')!;

      expect(p.cost, '');
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
      // No expected-hours or weight field exists on /projects/tasks/, so these
      // stay null — a 0/1 default would be indistinguishable from a stored
      // value on the detail page.
      expect(t.expHrs, isNull);
      expect(t.progress, 39); // computed_progress wins over the '0.000000' string
      expect(t.weight, isNull);
      expect(t.dept, '');
      expect(t.color.name, '');
      expect(t.subtasks, isEmpty);
      expect(t.waitingOn, isEmpty); // slim rows expose pending_dependency_count only
      expect(t.notes, isEmpty);
      expect(t.actualStart, isNull);
      expect(t.actualEnd, isNull);
      expect(t.fromTicket, isNull);
    });

    test('the row states its own project name, type and blocker count', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow())!;

      // Carried on the row, so a task on a project the list never loaded still
      // names it. The card used to resolve this against the loaded project set
      // and show "—" whenever that missed.
      expect(t.projectName, 'Technopark Tejaswini — 4F office interiors');
      // The id is what `type__in` wants; the name is what the drawer shows.
      expect(t.typeId, 'fb59b033-0000-0000-0000-000000000004');
      expect(t.typeName, 'Installation');
      // Slim rows carry the count, not the edges — this is the only thing the
      // list's "Waiting on N" badge can read.
      expect(t.pendingDeps, 1);
      expect(t.waitingOn, isEmpty);
    });

    test('is_overdue comes from the server, not the frozen prototype clock', () {
      expect(OpsTasksRemoteDataSource.mapOpsTask(slimRow())!.isOverdue, isFalse);
      expect(
        OpsTasksRemoteDataSource.mapOpsTask(slimRow()..['is_overdue'] = true)!
            .isOverdue,
        isTrue,
      );
      // Absent (mock rows) stays null, so the caller keeps its date fallback
      // instead of reading a missing flag as "not overdue".
      expect(
        OpsTasksRemoteDataSource.mapOpsTask(slimRow()..remove('is_overdue'))!
            .isOverdue,
        isNull,
      );
    });

    test('a standalone task has no project name to show', () {
      final row = slimRow()
        ..['project'] = null
        ..['project_name'] = null;
      final t = OpsTasksRemoteDataSource.mapOpsTask(row)!;

      expect(t.projId, '');
      expect(t.projectName, '');
    });

    test('the full row fills what the slim projection drops', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow()
        ..['description'] = 'Walk the site with the client.'
        ..['exp_start_date'] = '2026-06-28T09:00:00'
        ..['department'] = 'Snagging'
        ..['dependencies'] = [
          {'task_depends_on_id': 'edge-1', 'task_id': 'blocker-1', 'subject': 'First fix'},
          {'task_depends_on_id': 'edge-2', 'task_id': 'blocker-2', 'subject': 'Second fix'},
        ])!;

      // All four are absent from `?view=list`, so the edit form prefilled them
      // blank whatever was stored.
      expect(t.desc, 'Walk the site with the client.');
      expect(t.start, '28 Jun 2026');
      expect(t.startTime, '9:00 AM');
      expect(t.dept, 'Snagging');
      // The edge's `task_id` is the *other* task, not the edge id.
      expect(t.waitingOn, ['blocker-1', 'blocker-2']);
    });

    test('the detail-only decimals, code and colour are read, not invented', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow()
        ..['task_code'] = 'PRJ-1010-t3'
        ..['subtask_count'] = 4
        ..['subtask_done_count'] = 3
        // Fixed-point strings on the wire, and the weight is fractional —
        // rounding it to an int would be a silent edit.
        ..['expected_time'] = '24.000000'
        ..['task_weight'] = '3.500000'
        ..['color'] = '#E74C3C')!;

      expect(t.code, 'PRJ-1010-t3');
      expect(t.subtaskCount, 4);
      expect(t.subtaskDoneCount, 3);
      expect(t.expHrs, 24.0);
      expect(t.weight, 3.5);
      expect(t.color.name, '#E74C3C');
      expect(t.color.hex, const Color(0xFFE74C3C));
      // "24 hrs", not "24.0 hrs".
      expect(opsDecimalLabel(t.expHrs!), '24');
      expect(opsDecimalLabel(t.weight!), '3.5');
    });

    test('a colour the app cannot parse keeps the label and greys the swatch', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow()..['color'] = 'aubergine')!;
      expect(t.color.name, 'aubergine');
      expect(t.color.hex, OpsTasksRemoteDataSource.neutralTag.hex);
    });

    test('dependency edges arrive labelled, in both directions', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow()
        ..['dependencies'] = [
          {
            'task_depends_on_id': 'edge-1',
            'task_id': 'blocker-1',
            'subject': 'Electrical first fix',
            'status_name': 'Open',
            'is_closed': false,
          },
        ]
        ..['dependents'] = [
          {
            'task_depends_on_id': 'edge-2',
            'task_id': 'waiter-1',
            'subject': 'Client walkthrough',
            'status_name': 'Completed',
            'is_closed': true,
          },
        ])!;

      // Labels come free on detail, so a chip needs no second lookup against
      // the full task list — which is what the screen used to do.
      expect(t.deps.single.subject, 'Electrical first fix');
      expect(t.deps.single.edgeId, 'edge-1'); // what a DELETE removes
      expect(t.deps.single.isClosed, isFalse);
      expect(t.blocking.single.subject, 'Client walkthrough');
      expect(t.blocking.single.isClosed, isTrue);
    });

    test('an edge with no other-task id is dropped, not shown unopenable', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow()
        ..['dependencies'] = [
          {'task_depends_on_id': 'edge-1', 'subject': 'Orphan'},
          {'task_depends_on_id': 'edge-2', 'task_id': 'ok-1', 'subject': 'Real'},
        ])!;

      expect(t.deps.map((d) => d.taskId), ['ok-1']);
      expect(t.waitingOn, ['ok-1']);
    });

    test('a slim row keeps the detail-only fields empty rather than guessing', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow())!;

      expect(t.start, '');
      expect(t.startTime, '');
      expect(t.dept, '');
      expect(t.waitingOn, isEmpty);
    });

    test('subtask_count is carried — subtasks themselves never are', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow()..['subtask_count'] = 3)!;

      // The edit form reads the count to decide whether progress is rolled up
      // from children or set by hand; the embedded list is always empty, so
      // `subtasks.isEmpty` on its own said "manual" for every task.
      expect(t.subtaskCount, 3);
      expect(t.subtasks, isEmpty);
      expect(OpsTasksRemoteDataSource.mapOpsTask(slimRow())!.subtaskCount, 0);
    });

    test('task_group is carried, so the lane picker can preselect', () {
      final t = OpsTasksRemoteDataSource.mapOpsTask(slimRow())!;
      expect(t.groupId, '7f39d91e-0000-0000-0000-000000000003');
      expect(t.group, 'Site Work');
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
      expect(t.projectName, '');
      expect(t.typeId, '');
      expect(t.pendingDeps, 0);
      expect(t.isOverdue, isNull);
    });
  });

  group('OpsTasksRemoteDataSource.mapActivity', () {
    Map<String, dynamic> row({String? summary, String? eventType, String? action}) => {
          'audit_log_id': 'log-1',
          'summary': summary ?? 'Task created',
          'event_type': eventType ?? 'created',
          'action': action ?? 'create',
          'user_full_name': 'Admin Acme',
          'timestamp': '2026-08-12T13:17:42.694800Z',
        };

    test('the summary is the sentence — the feed is humanized server-side', () {
      final e = OpsTasksRemoteDataSource.mapActivity(row(), 0)!;
      expect(e.id, 'log-1');
      expect(e.title, 'Task created');
      expect(e.kind, AuditEventKind.created);
      expect(e.actor, 'Admin Acme');
      expect(e.at, isNotNull);
    });

    test('a status move resolves its uuid to the org name', () {
      // The server humanizes the sentence but leaves the FK raw, so without the
      // catalog this row puts a uuid in front of the user.
      const id = '7803f448-03a7-4a77-8bf0-5918f50655b5';
      final e = OpsTasksRemoteDataSource.mapActivity(
        row(summary: 'Status changed to $id', eventType: 'field_changed', action: 'update'),
        0,
        statusNames: const {id: 'Completed'},
      )!;
      expect(e.title, 'Status changed to Completed');
      expect(e.kind, AuditEventKind.statusChanged);
    });

    test('an unknown status uuid is left as it is, not dropped', () {
      const id = '11111111-2222-3333-4444-555555555555';
      final e = OpsTasksRemoteDataSource.mapActivity(
        row(summary: 'Status changed to $id'), 0)!;
      expect(e.title, 'Status changed to $id');
    });

    test('a row with no summary is skipped rather than rendered blank', () {
      expect(OpsTasksRemoteDataSource.mapActivity(row(summary: '  '), 0), isNull);
    });
  });
}
