import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/data/mock/mock_users.dart';
import 'package:clozrapp/features/helpdesk/infrastructure/data_sources/remote/tickets_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixture → Ticket assertions for the issues (helpdesk tickets) mapper.
/// Field names mirror `crm/serializers/issue.py`.
void main() {
  const meUuid = '11111111-2222-3333-4444-555555555555';
  const otherUuid = '99999999-8888-7777-6666-555555555555';
  const custUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const projUuid = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';

  Map<String, dynamic> fullRow() => {
        'issue_id': 'e1000000-0000-0000-0000-000000000001',
        'reference': 'TKT-0042',
        'subject': 'AC unit not cooling in trial room',
        'description': 'Stops cooling after 20 minutes.',
        'priority': 'Critical',
        'channel': 'whatsapp',
        'channel_display': 'WhatsApp',
        'type_name': 'Customer Complaint',
        'issue_type': 'c2000000-0000-0000-0000-000000000002',
        'status': {
          'issue_status_id': 's3000000-0000-0000-0000-000000000003',
          'name': 'On Hold',
          'is_on_hold': true,
        },
        'assigned_to': meUuid,
        'assigned_to_name': 'Manoj Varma',
        'customer': custUuid,
        'customer_name': 'Kalyan Silks',
        'product': 'p4000000-0000-0000-0000-000000000004',
        'product_name': 'AMC / Maintenance',
        'project': projUuid,
        'project_name': 'Showroom fit-out',
        'created_at': '2026-07-09T09:00:00Z',
        'first_responded_at': '2026-07-09T10:15:00Z',
        'first_response_due_at': '2026-07-09T13:00:00Z',
        'sla_deadline': '2026-07-14T18:00:00Z',
        'resolution_date': null,
      };

  setUp(() => UserDirectory.currentUserId = meUuid);
  tearDown(UserDirectory.reset);

  group('mapTicket — full row', () {
    test('maps identity, subject and description', () {
      final t = TicketsRemoteDataSource.mapTicket(fullRow())!;
      expect(t.id, 'e1000000-0000-0000-0000-000000000001');
      expect(t.subject, 'AC unit not cooling in trial room');
      expect(t.desc, 'Stops cooling after 20 minutes.');
    });

    test('maps nested status name onto the UI key set', () {
      final t = TicketsRemoteDataSource.mapTicket(fullRow())!;
      expect(t.status, 'pending'); // "On Hold" → pending
    });

    test('maps backend Critical priority to UI Urgent', () {
      final t = TicketsRemoteDataSource.mapTicket(fullRow())!;
      expect(t.pri, 'Urgent');
    });

    test('keeps the org issue type as the category', () {
      final t = TicketsRemoteDataSource.mapTicket(fullRow())!;
      // The org's own vocabulary, not a fold onto three invented words — this
      // org's types are Billing / Integration / Support, none of which survive
      // a fold, so a category edit could never be shown back to the user.
      expect(t.cat, 'Customer Complaint');
    });

    test('maps linkage: customer uuid, product name, project uuid', () {
      final t = TicketsRemoteDataSource.mapTicket(fullRow())!;
      expect(t.custId, custUuid);
      expect(t.product, 'AMC / Maintenance');
      expect(t.projId, projUuid);
      expect(t.taskId, isNull);
      expect(t.channel, 'WhatsApp');
    });

    test('maps SLA fields when present (raw ISO kept, labels derived)', () {
      final t = TicketsRemoteDataSource.mapTicket(fullRow())!;
      expect(t.respByISO, '2026-07-09T13:00:00Z');
      expect(t.respByLabel, isNotNull);
      expect(t.resolveByISO, '2026-07-14T18:00:00Z');
      expect(t.resolveByLabel, isNotNull);
      expect(t.created, contains('Jul 2026'));
      expect(t.responded, isNotNull);
      expect(t.resolved, isNull);
    });

    test('maps the signed-in assignee uuid to the "me" sentinel', () {
      final t = TicketsRemoteDataSource.mapTicket(fullRow())!;
      expect(t.assignees, ['me']);
      expect(t.isMine, isTrue);
    });
  });

  group('mapTicket — assignees', () {
    test('keeps other users as uuids and registers their names', () {
      final row = fullRow()
        ..['assigned_to'] = otherUuid
        ..['assigned_to_name'] = 'Deepa Nair';
      final t = TicketsRemoteDataSource.mapTicket(row)!;
      expect(t.assignees, [otherUuid]);
      expect(t.isMine, isFalse);
      expect(MockUsers.of(otherUuid).name, 'Deepa Nair');
    });

    test('registers embedded user objects via registerJson', () {
      final row = fullRow()
        ..['assigned_to'] = {'user_id': otherUuid, 'full_name': 'Ravi Kumar'};
      final t = TicketsRemoteDataSource.mapTicket(row)!;
      expect(t.assignees, [otherUuid]);
      expect(MockUsers.of(otherUuid).name, 'Ravi Kumar');
    });
  });

  group('mapTicket — status / priority / category variants', () {
    String statusOf(Object? status) => TicketsRemoteDataSource.mapTicket(
        {'issue_id': 'x', 'status': status})!.status;

    test('status names map onto the fixed ticket keys', () {
      expect(statusOf({'name': 'New'}), 'new');
      expect(statusOf({'name': 'Open'}), 'open');
      expect(statusOf({'name': 'Waiting on Customer'}), 'pending');
      expect(statusOf({'name': 'Resolved'}), 'resolved');
      expect(statusOf({'name': 'Closed'}), 'closed');
      expect(statusOf(null), 'open'); // no status → sensible default
    });

    test('priorities map onto the UI vocabulary', () {
      String priOf(String? v) => TicketsRemoteDataSource.mapTicket(
          {'issue_id': 'x', 'priority': v})!.pri;
      expect(priOf('Low'), 'Low');
      expect(priOf('Medium'), 'Medium');
      expect(priOf('High'), 'High');
      expect(priOf('Critical'), 'Urgent');
      expect(priOf(null), 'Medium');
    });

    test('issue-type names are kept verbatim; only a missing type folds', () {
      String catOf(String? name) => TicketsRemoteDataSource.mapTicket(
          {'issue_id': 'x', 'type_name': name})!.cat;
      expect(catOf('Customer Complaint'), 'Customer Complaint');
      expect(catOf('Service Request'), 'Service Request');
      expect(catOf('Integration'), 'Integration');
      expect(catOf(null), 'Query');
    });
  });

  group('mapTicket — null tolerance', () {
    test('a bare row maps entirely to safe defaults', () {
      final t = TicketsRemoteDataSource.mapTicket({'issue_id': 'x'})!;
      expect(t.subject, '');
      expect(t.cat, 'Query');
      expect(t.custId, '');
      expect(t.contact, '');
      expect(t.channel, 'Email');
      expect(t.status, 'open');
      expect(t.pri, 'Medium');
      expect(t.assignees, isEmpty);
      expect(t.product, isNull);
      expect(t.projId, isNull);
      expect(t.taskId, isNull);
      expect(t.created, '');
      expect(t.responded, isNull);
      expect(t.resolved, isNull);
      expect(t.respByISO, isNull);
      expect(t.respByLabel, isNull);
      expect(t.resolveByISO, isNull);
      expect(t.resolveByLabel, isNull);
      expect(t.desc, '');
    });

    test('wrong-typed fields never throw and fall back to defaults', () {
      final t = TicketsRemoteDataSource.mapTicket({
        'issue_id': 'x',
        'subject': 42,
        'priority': 7,
        'status': ['bad'],
        'assigned_to': 12,
        'customer': 3.14,
        'sla_deadline': 123,
        'first_response_due_at': 'not-a-date',
        'description': false,
      })!;
      expect(t.subject, '');
      expect(t.pri, 'Medium');
      expect(t.status, 'open');
      expect(t.assignees, isEmpty);
      expect(t.custId, '');
      expect(t.resolveByISO, isNull);
      expect(t.respByISO, isNull); // unparseable ISO dropped, label too
      expect(t.respByLabel, isNull);
      expect(t.desc, '');
    });
  });

  group('mapTickets — list hygiene', () {
    test('skips rows without an issue_id and non-map entries', () {
      final tickets = TicketsRemoteDataSource.mapTickets([
        fullRow(),
        {'subject': 'no id — must be skipped'},
        'garbage',
        null,
        {'issue_id': 'e2000000-0000-0000-0000-000000000002'},
      ]);
      expect(tickets, hasLength(2));
      expect(tickets.first.id, 'e1000000-0000-0000-0000-000000000001');
      expect(tickets.last.id, 'e2000000-0000-0000-0000-000000000002');
    });
  });
}
