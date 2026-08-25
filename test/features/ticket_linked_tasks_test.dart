import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/helpdesk/infrastructure/data_sources/remote/tickets_remote_ds.dart';

/// A row exactly as `GET /crm/issues/{id}/tasks/` serves it — the **projects**
/// `TaskSerializer`, verified against the dev backend.
Map<String, dynamic> _row() => {
      'task_id': 'f2871021-8f39-4502-b982-0f11c6769621',
      'subject': 'Update the help-centre article with the new steps',
      'project': null,
      'ticket': 'c7c537e8-e2f7-44a7-a3c8-3f12981d917f',
      'status': null,
      'priority': 'Medium',
      'assigned_to': {
        'user_id': '43afca7b-ffce-4690-9560-34cb09e2c2e0',
        'username': 'suresh.kapoor.1@seed.acme.com',
        'full_name': 'Suresh Kapoor',
      },
    };

void main() {
  group('linked task mapping', () {
    test('reads subject, priority and the nested assignee', () {
      final t = TicketsRemoteDataSource.linkedTaskFromJson(_row());
      expect(t.id, 'f2871021-8f39-4502-b982-0f11c6769621');
      expect(t.subject, 'Update the help-centre article with the new steps');
      expect(t.priority, 'Medium');
      expect(t.assigneeName, 'Suresh Kapoor');
      expect(t.display, t.subject);
    });

    test('a null status and project are "unset", not a crash', () {
      final t = TicketsRemoteDataSource.linkedTaskFromJson(_row());
      expect(t.status, '');
      expect(t.projectId, isNull);
    });

    test('nested status/project objects unwrap to name and id', () {
      final t = TicketsRemoteDataSource.linkedTaskFromJson({
        ..._row(),
        'status': {'name': 'In Progress'},
        'project': {'project_id': 'p-1', 'name': 'Website revamp'},
      });
      expect(t.status, 'In Progress');
      expect(t.projectId, 'p-1');
    });

    test('a row with no subject still addresses its task', () {
      final t = TicketsRemoteDataSource.linkedTaskFromJson(
          {..._row(), 'subject': null});
      expect(t.subject, '');
      expect(t.display, t.id);
    });
  });

  _writePayloadTests();
  _categoryTests();
}

/// What the create/edit ticket forms actually send. `product_id` / `project_id`
/// were dropped entirely before, so picking either was a silent no-op.
void _writePayloadTests() {
  group('ticket write payload', () {
    test('carries the product and project links', () {
      final out = TicketsRemoteDataSource.writePayload({
        'subject': 'Broken export',
        'priority': 'Urgent',
        'product_id': '37d51ece-a7ca-4752-aa28-6bd3268eb76c',
        'project_id': '1d7c185a-ee1f-4783-a661-5b084ef39b1e',
      });
      expect(out['product_id'], '37d51ece-a7ca-4752-aa28-6bd3268eb76c');
      expect(out['project_id'], '1d7c185a-ee1f-4783-a661-5b084ef39b1e');
      // UI "Urgent" is the backend's "Critical".
      expect(out['priority'], 'Critical');
    });

    test('an explicit null is kept — that is how a link is cleared', () {
      final out = TicketsRemoteDataSource.writePayload(
          {'product_id': null, 'project_id': null});
      expect(out.containsKey('product_id'), isTrue);
      expect(out['product_id'], isNull);
      expect(out['project_id'], isNull);
    });

    test('an absent key stays absent, so it is left untouched', () {
      final out = TicketsRemoteDataSource.writePayload({'subject': 'x'});
      expect(out.containsKey('product_id'), isFalse);
      expect(out.containsKey('project_id'), isFalse);
    });

    test('carries the org issue type the category chips now offer', () {
      final out = TicketsRemoteDataSource.writePayload(
          {'issue_type': '44b11cd3-5d89-4be3-b058-6e0c7f2a3bb4'});
      expect(out['issue_type'], '44b11cd3-5d89-4be3-b058-6e0c7f2a3bb4');
    });

    test('the built-in category words are never sent as a type', () {
      final out = TicketsRemoteDataSource.writePayload({'issue_type': 'Complaint'});
      expect(out.containsKey('issue_type'), isFalse);
    });

    test('a mock-mode id is dropped rather than sent as a bad uuid', () {
      final out = TicketsRemoteDataSource.writePayload(
          {'product_id': 'P-01', 'project_id': 'PRJ-2401'});
      expect(out.containsKey('product_id'), isFalse);
      expect(out.containsKey('project_id'), isFalse);
    });
  });
}

/// The org calls its categories Billing / Integration / Support; the app used to
/// fold every one of them into Complaint / Request / Query, so a category edit
/// could never show up on the detail screen.
void _categoryTests() {
  group('ticket category', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
          'issue_id': 'i-1',
          'subject': 's',
          ...extra,
        };

    test('reads the org type name and keeps its id for the write', () {
      final t = TicketsRemoteDataSource.mapTicket(row({
        'type_name': 'Integration',
        'issue_type': '68456675-62d5-4391-9ffe-167df2bdd772',
      }))!;
      expect(t.cat, 'Integration');
      expect(t.typeId, '68456675-62d5-4391-9ffe-167df2bdd772');
    });

    test('a nested issue_type object works too', () {
      final t = TicketsRemoteDataSource.mapTicket(row({
        'issue_type': {'issue_type_id': 'type-1', 'name': 'Billing'},
      }))!;
      expect(t.cat, 'Billing');
      expect(t.typeId, 'type-1');
    });

    test('a row with no type falls back to the built-in vocabulary', () {
      final t = TicketsRemoteDataSource.mapTicket(row(const {}))!;
      expect(t.cat, 'Query');
      expect(t.typeId, '');
    });
  });
}
