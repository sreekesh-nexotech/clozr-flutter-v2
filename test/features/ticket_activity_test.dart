// The ticket detail's trail read the org-wide `/access-control/audit-logs/`,
// which needs `view_audit_log` and answered **0 rows** for a ticket whose own
// feed had 8. helpdesk.md §10 gives the ticket-native endpoint, gated by
// `view_issue` and pre-humanized. Fixtures are the live dev-backend rows.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/domain/entities/audit_entry.dart';
import 'package:clozrapp/features/helpdesk/infrastructure/data_sources/remote/tickets_remote_ds.dart';

Map<String, dynamic> _row({
  required String event,
  String? summary,
  Map<String, dynamic>? actor,
}) =>
    {
      'audit_log_id': 'a1',
      'event_type': event,
      'summary': summary,
      'actor': actor ??
          {'user_id': 'u1', 'name': 'Admin Acme', 'is_system': false},
      'timestamp': '2026-08-13T07:13:43Z',
    };

void main() {
  group('the server writes the sentence', () {
    test('the summary is the row title, attributed to the actor', () {
      final e = TicketsRemoteDataSource.activityFromJson(
        _row(event: 'field_changed', summary: 'Assignee changed to Pooja Chopra'),
      )!;

      expect(e.title, 'Assignee changed to Pooja Chopra');
      expect(e.subtitle, 'by Admin Acme');
      expect(e.kind, AuditEventKind.fieldChanged);
    });

    test('a system event reads as System, not as a person', () {
      final e = TicketsRemoteDataSource.activityFromJson(
        _row(
          event: 'sla_breached',
          summary: 'SLA breached',
          actor: {'user_id': null, 'name': 'System', 'is_system': true},
        ),
      )!;

      expect(e.subtitle, 'System');
      expect(e.kind, AuditEventKind.other); // red, like a breach should read
    });

    test('lifecycle events read as status moves', () {
      expect(
        TicketsRemoteDataSource.activityFromJson(
          _row(event: 'reopened', summary: 'Ticket reopened'),
        )!.kind,
        AuditEventKind.statusChanged,
      );
      expect(
        TicketsRemoteDataSource.activityFromJson(
          _row(event: 'reply_sent', summary: 'Reply sent'),
        )!.kind,
        AuditEventKind.noteAdded,
      );
    });
  });

  group('uuids the server left in the sentence', () {
    test('are swapped for the names they belong to', () {
      // Live example: "Status changed to f164d805-…" — the server does not
      // resolve the id, so the card would show a raw uuid to the user.
      final e = TicketsRemoteDataSource.activityFromJson(
        _row(event: 'field_changed', summary: 'Status changed to f164d805-c961'),
        names: {'f164d805-c961': 'Open'},
      )!;

      expect(e.title, 'Status changed to Open');
    });

    test('an unknown id is left alone rather than blanked', () {
      final e = TicketsRemoteDataSource.activityFromJson(
        _row(event: 'field_changed', summary: 'Status changed to 9999-abcd'),
        names: {'f164d805-c961': 'Open'},
      )!;

      expect(e.title, 'Status changed to 9999-abcd');
    });
  });

  test('a row with no summary still says something', () {
    final e = TicketsRemoteDataSource.activityFromJson(
      _row(event: 'sla_paused', summary: null),
    )!;

    expect(e.title, 'Sla paused');
  });

  test('a row with no id is skipped, never fatal', () {
    expect(
      TicketsRemoteDataSource.activityFromJson({'event_type': 'created'}),
      isNull,
    );
  });
}
