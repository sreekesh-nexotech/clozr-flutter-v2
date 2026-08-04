import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/crm_tasks_remote_ds.dart';

void main() {
  final now = DateTime(2026, 6, 18, 9, 30);

  tearDown(UserDirectory.reset);

  Map<String, dynamic> row() => {
        'task_id': 'a5e90248-1111-2222-3333-444455556666',
        'title': 'Call to discuss scope — Kalyan Silks',
        'task_type': 'Call',
        'status': 'To do',
        'priority': {
          'task_priority_id': 'p-1',
          'name': 'High',
          'color': '#EF4444',
        },
        'due_date': '2026-06-16',
        'due_time': '11:00:00',
        'assigned_to': {
          'user_id': 'u-anjana',
          'full_name': 'Anjana Menon',
        },
        'related_to': {
          'model': 'lead',
          'id': 'lead-uuid-1',
          'label': 'Kalyan Silks',
        },
        'description': 'Intro call',
        'created_at': '2026-06-14T09:41:00Z',
      };

  group('CrmTasksRemoteDataSource.taskFromJson', () {
    test('maps a full list row onto CrmTask', () {
      final t = CrmTasksRemoteDataSource.taskFromJson(row(), now: now)!;
      expect(t.id, 'a5e90248-1111-2222-3333-444455556666');
      expect(t.title, 'Call to discuss scope — Kalyan Silks');
      expect(t.type, 'Call');
      expect(t.leadId, 'lead-uuid-1');
      expect(t.status, 'todo');
      expect(t.priority, 'High');
      expect(t.assignee, 'u-anjana');
      expect(t.due, '16 Jun 2026');
      expect(t.dueNote, '2d overdue');
    });

    test('maps status display names onto the fixed UI keys', () {
      String statusOf(String name) => CrmTasksRemoteDataSource.taskFromJson(
            {...row(), 'status': name},
            now: now,
          )!
              .status;
      expect(statusOf('In Progress'), 'inprogress');
      expect(statusOf('Completed'), 'done');
      expect(statusOf('Done'), 'done');
      expect(statusOf('Blocked'), 'blocked');
      expect(statusOf('Open'), 'todo');
      expect(statusOf('Something Custom'), 'todo');
    });

    test('assignee becomes "me" for the signed-in user', () {
      UserDirectory.currentUserId = 'u-anjana';
      final t = CrmTasksRemoteDataSource.taskFromJson(row(), now: now)!;
      expect(t.assignee, 'me');
    });

    test('related_to null and non-lead variants leave leadId null', () {
      final noRelated =
          CrmTasksRemoteDataSource.taskFromJson({...row(), 'related_to': null}, now: now)!;
      expect(noRelated.leadId, isNull);

      final customer = CrmTasksRemoteDataSource.taskFromJson({
        ...row(),
        'related_to': {'model': 'customer', 'id': 'cust-1', 'label': 'Acme'},
      }, now: now)!;
      expect(customer.leadId, isNull);
    });

    test('is defensive: skips rows without task_id, tolerates junk fields', () {
      expect(CrmTasksRemoteDataSource.taskFromJson({'title': 'No id'}), isNull);
      expect(CrmTasksRemoteDataSource.taskFromJson({...row(), 'task_id': ''}), isNull);

      final junk = CrmTasksRemoteDataSource.taskFromJson({
        'task_id': 't-1',
        'title': null,
        'task_type': 42,
        'status': null,
        'priority': null,
        'assigned_to': 'not-a-map',
        'due_date': 'garbage',
        'related_to': 'not-a-map',
      }, now: now)!;
      expect(junk.title, '');
      expect(junk.type, '');
      expect(junk.status, 'todo');
      expect(junk.priority, 'Medium');
      expect(junk.assignee, '');
      expect(junk.due, '');
      expect(junk.dueNote, '');
    });

    test('mapRows drops only the malformed rows', () {
      final rows = [row(), {'title': 'no id'}, {...row(), 'task_id': 't-2'}];
      expect(CrmTasksRemoteDataSource.mapRows(rows, now: now).length, 2);
    });
  });

  group('CrmTasksRemoteDataSource.dueNoteFor', () {
    test('derives overdue / today / upcoming buckets from a fixed now', () {
      expect(CrmTasksRemoteDataSource.dueNoteFor(DateTime(2026, 6, 16), now: now), '2d overdue');
      expect(CrmTasksRemoteDataSource.dueNoteFor(DateTime(2026, 6, 17), now: now), '1d overdue');
      expect(CrmTasksRemoteDataSource.dueNoteFor(DateTime(2026, 6, 18), now: now), 'Today');
      expect(CrmTasksRemoteDataSource.dueNoteFor(DateTime(2026, 6, 21), now: now), 'In 3d');
      expect(CrmTasksRemoteDataSource.dueNoteFor(DateTime(2026, 6, 25), now: now), 'In 7d');
      expect(CrmTasksRemoteDataSource.dueNoteFor(DateTime(2026, 6, 26), now: now), '');
      expect(CrmTasksRemoteDataSource.dueNoteFor(null, now: now), '');
    });
  });

  group('CrmTasksRemoteDataSource.statusIdForKey', () {
    final statuses = [
      {'crm_task_status_id': 's-open', 'name': 'Open', 'status_type': 'open', 'is_default': true},
      {'crm_task_status_id': 's-prog', 'name': 'Working on it', 'status_type': 'in_progress'},
      {'crm_task_status_id': 's-done', 'name': 'Finished', 'status_type': 'completed'},
    ];

    test('resolves a UI key via name or status_type', () {
      expect(CrmTasksRemoteDataSource.statusIdForKey(statuses, 'todo'), 's-open');
      expect(CrmTasksRemoteDataSource.statusIdForKey(statuses, 'inprogress'), 's-prog');
      expect(CrmTasksRemoteDataSource.statusIdForKey(statuses, 'done'), 's-done');
      expect(CrmTasksRemoteDataSource.statusIdForKey(statuses, 'blocked'), isNull);
    });
  });

  group('CrmTasksRemoteDataSource.isoDateOrNull', () {
    test('accepts ISO and the UI display format, rejects junk', () {
      expect(CrmTasksRemoteDataSource.isoDateOrNull('2026-06-24'), '2026-06-24');
      expect(CrmTasksRemoteDataSource.isoDateOrNull('24 Jun 2026'), '2026-06-24');
      expect(CrmTasksRemoteDataSource.isoDateOrNull('garbage'), isNull);
      expect(CrmTasksRemoteDataSource.isoDateOrNull(''), isNull);
      expect(CrmTasksRemoteDataSource.isoDateOrNull(null), isNull);
    });
  });
}
