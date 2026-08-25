import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/followups_remote_ds.dart';

void main() {
  final now = DateTime(2026, 6, 18, 9, 30);

  tearDown(UserDirectory.reset);

  Map<String, dynamic> row() => {
        'task_id': 'f-uuid-1',
        'title': 'Follow up on sign-off',
        'task_type': 'Call',
        'is_followup': true,
        'status': 'Open',
        'due_date': '2026-06-20',
        'due_time': '09:30:00',
        'assigned_to': {'user_id': 'u-rahul', 'full_name': 'Rahul Nair'},
        'related_to': {
          'model': 'customer',
          'id': 'cust-uuid-1',
          'label': 'Kalyan Silks',
        },
        'description': 'Discuss scope and share ballpark',
      };

  group('FollowupsRemoteDataSource.followupFromJson', () {
    test('maps a full row onto Followup (customer-linked)', () {
      final f = FollowupsRemoteDataSource.followupFromJson(row(), now: now)!;
      expect(f.id, 'f-uuid-1');
      expect(f.kind, 'Call');
      expect(f.contact, 'Kalyan Silks');
      expect(f.custId, 'cust-uuid-1');
      expect(f.leadId, isNull);
      expect(f.company, 'Kalyan Silks');
      expect(f.due, '20 Jun 2026');
      expect(f.time, '09:30');
      expect(f.status, 'due'); // future due date, not completed
      expect(f.owner, 'u-rahul');
      // Both fields are kept — the description no longer overwrites the title.
      expect(f.title, isNotEmpty);
      expect(f.description, 'Discuss scope and share ballpark');
      expect(f.agenda, 'Discuss scope and share ballpark');
    });

    test('derives done from a completed-mapped status regardless of date', () {
      final f = FollowupsRemoteDataSource.followupFromJson({
        ...row(),
        'status': 'Completed',
        'due_date': '2026-06-01', // long past — done still wins
      }, now: now)!;
      expect(f.status, 'done');
    });

    test('derives overdue vs due from the due date when not completed', () {
      final overdue = FollowupsRemoteDataSource.followupFromJson(
          {...row(), 'due_date': '2026-06-17'}, now: now)!;
      expect(overdue.status, 'overdue');

      final today = FollowupsRemoteDataSource.followupFromJson(
          {...row(), 'due_date': '2026-06-18'}, now: now)!;
      expect(today.status, 'due');

      final noDate = FollowupsRemoteDataSource.followupFromJson(
          {...row(), 'due_date': null}, now: now)!;
      expect(noDate.status, 'due');
      expect(noDate.due, '');
    });

    test('lead-linked rows set leadId; unlinked rows fall back to the title', () {
      final lead = FollowupsRemoteDataSource.followupFromJson({
        ...row(),
        'related_to': {'model': 'lead', 'id': 'lead-uuid-9', 'label': 'Infopark'},
      }, now: now)!;
      expect(lead.leadId, 'lead-uuid-9');
      expect(lead.custId, isNull);
      expect(lead.contact, 'Infopark');

      final none = FollowupsRemoteDataSource.followupFromJson(
          {...row(), 'related_to': null}, now: now)!;
      expect(none.custId, isNull);
      expect(none.leadId, isNull);
      expect(none.contact, 'Follow up on sign-off');
      expect(none.company, '');
    });

    test('owner becomes "me" for the signed-in user', () {
      UserDirectory.currentUserId = 'u-rahul';
      final f = FollowupsRemoteDataSource.followupFromJson(row(), now: now)!;
      expect(f.owner, 'me');
    });

    test('title survives an empty description; agenda falls back to it', () {
      final noDesc = FollowupsRemoteDataSource.followupFromJson(
          {...row(), 'description': null}, now: now)!;
      expect(noDesc.title, 'Follow up on sign-off');
      expect(noDesc.description, isEmpty);
      expect(noDesc.agenda, 'Follow up on sign-off');

      final blank = FollowupsRemoteDataSource.followupFromJson(
          {...row(), 'description': '   '}, now: now)!;
      expect(blank.title, 'Follow up on sign-off');
      expect(blank.agenda, 'Follow up on sign-off');
    });

    test('is defensive: rows without task_id are skipped', () {
      expect(FollowupsRemoteDataSource.followupFromJson({'title': 'x'}), isNull);
      expect(
          FollowupsRemoteDataSource.followupFromJson({...row(), 'task_id': null}),
          isNull);
      final rows = [row(), {'no': 'id'}];
      expect(FollowupsRemoteDataSource.mapRows(rows, now: now).length, 1);
    });
  });

  group('FollowupsRemoteDataSource.trimTime', () {
    test('trims seconds and tolerates null/short values', () {
      expect(FollowupsRemoteDataSource.trimTime('09:30:00'), '09:30');
      expect(FollowupsRemoteDataSource.trimTime('14:05'), '14:05');
      expect(FollowupsRemoteDataSource.trimTime(null), '');
      expect(FollowupsRemoteDataSource.trimTime(930), '');
    });
  });

  group('FollowupsRemoteDataSource.openStatusId', () {
    test('prefers the default open status, then any open, then any non-done', () {
      final statuses = [
        {'crm_task_status_id': 's-a', 'name': 'Backlog', 'status_type': 'open'},
        {'crm_task_status_id': 's-b', 'name': 'Open', 'status_type': 'open', 'is_default': true},
        {'crm_task_status_id': 's-c', 'name': 'Finished', 'status_type': 'completed'},
      ];
      expect(FollowupsRemoteDataSource.openStatusId(statuses), 's-b');

      final noDefault = [statuses[0], statuses[2]];
      expect(FollowupsRemoteDataSource.openStatusId(noDefault), 's-a');

      final noOpenType = [
        {'crm_task_status_id': 's-p', 'name': 'Working', 'status_type': 'in_progress'},
        {'crm_task_status_id': 's-c', 'name': 'Finished', 'status_type': 'completed'},
      ];
      expect(FollowupsRemoteDataSource.openStatusId(noOpenType), 's-p');

      expect(FollowupsRemoteDataSource.openStatusId(const []), isNull);
    });
  });
}
