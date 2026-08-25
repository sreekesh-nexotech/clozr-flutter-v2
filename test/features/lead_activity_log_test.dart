// The lead Activity log used to be four hard-coded rows ("Call logged", "Site
// visit scheduled") with the lead's name interpolated. It now reads the real
// audit trail. Fixtures are the live dev-backend shapes — note the generic
// /access-control/audit-logs/ endpoint sends NO `summary`/`event_type`, unlike
// the project feeds, so everything readable is derived here.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/domain/entities/audit_entry.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/audit_log_remote_ds.dart';

Map<String, dynamic> _row({
  required String id,
  String action = 'update',
  String actor = 'Admin Acme',
  String at = '2026-08-06T11:36:26.558725Z',
  Map<String, dynamic>? changes,
}) =>
    {
      'audit_log_id': id,
      'action': action,
      'model_name': 'Lead',
      'record_id': 'lead-1',
      'user_full_name': actor,
      'timestamp': at,
      if (changes != null) 'changes': changes,
    };

const _statusNames = {
  'st-new': 'New',
  'st-qualified': 'Qualified',
};

void main() {
  group('status changes', () {
    test('resolve the id to the org stage name, with the previous one', () {
      final e = AuditLogRemoteDataSource.mapEntry(
        _row(id: 'a1', changes: {
          'before': {'status_id': 'st-new'},
          'request_body': {'status_id': 'st-qualified'},
        }),
        statusNames: _statusNames,
      )!;

      expect(e.kind, AuditEventKind.statusChanged);
      expect(e.title, 'Status changed to Qualified');
      expect(e.subtitle, 'From New · by Admin Acme');
    });

    test('an unknown stage still reads sensibly, never as a uuid', () {
      final e = AuditLogRemoteDataSource.mapEntry(
        _row(id: 'a1', changes: {
          'request_body': {'status_id': '0d49d620-1b84-4f0c-a049-4301e7816235'},
        }),
      )!;

      expect(e.title, 'Status changed');
      expect(e.title, isNot(contains('0d49d620')));
    });
  });

  group('child writes', () {
    test('a note rolled up onto the lead reads as "Note added"', () {
      final e = AuditLogRemoteDataSource.mapEntry(
        _row(id: 'a2', changes: {
          'related_change': {'type': 'Note', 'action': 'create', 'record_id': 'n1'},
        }),
      )!;

      expect(e.kind, AuditEventKind.noteAdded);
      expect(e.title, 'Note added');
      expect(e.subtitle, 'by Admin Acme');
    });

    test('other child types keep their own noun', () {
      final e = AuditLogRemoteDataSource.mapEntry(
        _row(id: 'a3', changes: {
          'related_change': {'type': 'Attachment', 'action': 'create'},
        }),
      )!;

      expect(e.kind, AuditEventKind.childAdded);
      expect(e.title, 'Attachment added');
    });
  });

  group('field writes', () {
    test('one field names it, with the _id suffix stripped', () {
      final e = AuditLogRemoteDataSource.mapEntry(
        _row(id: 'a4', changes: {
          'request_body': {'lead_owner_id': 'u1'},
        }),
      )!;

      expect(e.kind, AuditEventKind.fieldChanged);
      expect(e.title, 'Lead owner updated');
    });

    test('several fields are counted, then listed', () {
      final e = AuditLogRemoteDataSource.mapEntry(
        _row(id: 'a5', changes: {
          'request_body': {'email': 'a@b.c', 'mobile_no': '+91', 'website': 'x'},
        }),
      )!;

      expect(e.title, '3 fields updated');
      expect(e.subtitle, startsWith('Email, Mobile no, Website'));
    });
  });

  group('create / delete', () {
    test('a create row is the "Lead created" entry', () {
      final e = AuditLogRemoteDataSource.mapEntry(_row(id: 'a6', action: 'create'))!;

      expect(e.kind, AuditEventKind.created);
      expect(e.title, 'Lead created');
    });

    test('a delete row is marked as such', () {
      final e = AuditLogRemoteDataSource.mapEntry(_row(id: 'a7', action: 'delete'))!;

      expect(e.kind, AuditEventKind.deleted);
    });
  });

  group('robustness', () {
    test('a row with no audit_log_id is skipped, not rendered blank', () {
      expect(AuditLogRemoteDataSource.mapEntry({'action': 'update'}), isNull);
    });

    test('an unrecognised change shape still yields a readable row', () {
      final e = AuditLogRemoteDataSource.mapEntry(
        _row(id: 'a8', changes: {'something_new': true}),
      )!;

      expect(e.title, 'Record updated');
      expect(e.kind, AuditEventKind.other);
    });

    test('a missing actor leaves the byline empty rather than "by "', () {
      final e = AuditLogRemoteDataSource.mapEntry(
        _row(id: 'a9', actor: '', action: 'create'),
      )!;

      expect(e.subtitle, isEmpty);
    });

    test('mapEntries drops junk and keeps the order it was given', () {
      final entries = AuditLogRemoteDataSource.mapEntries([
        _row(id: 'a1', action: 'create'),
        'not a row',
        {'no': 'id'},
        _row(id: 'a2', changes: {
          'related_change': {'type': 'Note', 'action': 'create'},
        }),
      ]);

      expect(entries.map((e) => e.id).toList(), ['a1', 'a2']);
    });

    test('the timestamp is parsed for relative display', () {
      final e = AuditLogRemoteDataSource.mapEntry(_row(id: 'a1', action: 'create'))!;

      expect(e.at, isNotNull);
      expect(e.at!.year, 2026);
    });
  });

  // The helpdesk ticket trail was derived client-side — invented rows naming a
  // prototype user. It now reads the same audit endpoint (`model_name=Issue`,
  // 71 real rows on the dev backend), which raises lifecycle events of its own.
  group('issue events', () {
    AuditEntry map(Map<String, dynamic> changes) =>
        AuditLogRemoteDataSource.mapEntry(
          {
            'audit_log_id': 'a1',
            'action': 'update',
            'timestamp': '2026-08-12T17:45:00Z',
            'changes': changes,
          },
          recordLabel: 'Ticket',
        )!;

    test('an SLA breach reads as one, and as the system', () {
      // The live shape: `{"issue_event": {"data": {}, "type": "sla_breached"}}`.
      final e = map({
        'issue_event': {'data': <String, dynamic>{}, 'type': 'sla_breached'}
      });

      expect(e.title, 'SLA breached');
      expect(e.subtitle, 'System');
      expect(e.kind, AuditEventKind.other); // red, like a breach should read
    });

    test('lifecycle events read as status moves', () {
      expect(map({'issue_event': {'type': 'reopened'}}).title, 'Ticket reopened');
      expect(map({'issue_event': {'type': 'resolved'}}).kind,
          AuditEventKind.statusChanged);
    });

    test('an unknown event is humanised rather than swallowed', () {
      expect(map({'issue_event': {'type': 'merged_into_parent'}}).title,
          'Merged into parent');
    });
  });

  group('the record label', () {
    test('a create names the record it belongs to', () {
      Map<String, dynamic> createRow() => {
            'audit_log_id': 'c1',
            'action': 'create',
            'timestamp': '2026-08-12T17:45:00Z',
          };

      // Every feed used to say "Lead created", a quote's and a ticket's too.
      expect(
          AuditLogRemoteDataSource.mapEntry(createRow(), recordLabel: 'Ticket')!.title,
          'Ticket created');
      expect(
          AuditLogRemoteDataSource.mapEntry(createRow(), recordLabel: 'Quote')!.title,
          'Quote created');
      expect(AuditLogRemoteDataSource.mapEntry(createRow())!.title, 'Lead created');
    });
  });
}
