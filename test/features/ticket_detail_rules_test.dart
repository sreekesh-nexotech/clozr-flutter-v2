import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/helpdesk/application/ticket_detail_rules.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/ticket.dart';
import 'package:clozrapp/features/helpdesk/infrastructure/data_sources/remote/tickets_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row([Map<String, dynamic> extra = const {}]) => {
      'issue_id': '11111111-1111-1111-1111-111111111111',
      'reference': 'TKT-0042',
      'subject': 'Printer jams',
      'status': {'issue_status_id': 's1', 'name': 'Open', 'is_resolved': false, 'is_on_hold': false, 'color': '#3B82F6'},
      'priority': 'High',
      'channel': 'email',
      'created_at': '2026-10-27T09:00:00+05:30',
      ...extra,
    };

Ticket _t([Map<String, dynamic> extra = const {}]) => TicketsRemoteDataSource.mapTicket(_row(extra))!;

void main() {
  group('header and channel', () {
    test('sub-line falls back to Uncategorised / No customer', () {
      expect(ticketHeaderSubline(_t()), 'Uncategorised · No customer');
      expect(ticketHeaderSubline(_t({'type_name': 'Bug', 'customer_name': 'Acme'})), 'Bug · Acme');
    });

    test('via line uses the raw channel and time ago', () {
      final now = DateTime.parse('2026-10-27T12:00:00+05:30');
      expect(ticketViaLine(_t(), now: now), 'via email · 3h ago');
      expect(ticketViaLine(_t({'channel': null}), now: now), 'via unset · 3h ago');
    });

    test('channel labels and reply dispatch', () {
      expect(ticketChannelLabel('api'), 'API / Webhook');
      expect(ticketChannelLabel(null), 'Unset');
      expect(ticketChannelLabel('walk_in'), 'Walk in');
      expect(isReplyDispatchable('email'), isTrue);
      expect(isReplyDispatchable('whatsapp'), isTrue);
      expect(isReplyDispatchable('phone'), isFalse);
      expect(isReplyDispatchable(null), isFalse);
    });
  });

  group('lock and first response', () {
    test('a resolved-flag status locks the ticket', () {
      final resolved = _t({
        'status': {'issue_status_id': 's2', 'name': 'Duplicate', 'is_resolved': true},
      });
      expect(resolved.isLocked, isTrue);
      expect(_t().isLocked, isFalse);
      expect(canLogFirstResponse(resolved), isFalse);
    });

    test('log first response only while none is recorded', () {
      expect(canLogFirstResponse(_t()), isTrue);
      expect(canLogFirstResponse(_t({'first_responded_at': '2026-10-27T10:00:00+05:30'})), isFalse);
    });
  });

  group('SLA rows', () {
    test('no first-response target → no row', () {
      expect(firstResponseSeg(_t()), isNull);
    });

    test('first response met / paused / breached / due', () {
      final due = {'first_response_due_at': '2026-10-27T11:00:00+05:30'};
      expect(firstResponseSeg(_t({...due, 'first_responded_at': '2026-10-27T10:00:00+05:30'}))!.label, startsWith('Met · '));
      expect(
          firstResponseSeg(_t({
            ...due,
            'status': {'issue_status_id': 's', 'name': 'On Hold', 'is_on_hold': true},
          }))!
              .label,
          'Paused');
      final breached = firstResponseSeg(_t({...due, 'first_response_remaining_seconds': -60}))!;
      expect(breached.label, startsWith('Breached · was due '));
      expect(breached.tone, SlaTone.breached);
      expect(firstResponseSeg(_t({...due, 'first_response_remaining_seconds': 3900}))!.label, endsWith(' · 1h 5m left'));
    });

    test('resolution: resolved / no SLA / paused / at risk / overdue', () {
      expect(resolutionSeg(_t({'resolved_at': '2026-10-27T10:00:00+05:30'})).label, startsWith('Resolved · '));
      expect(resolutionSeg(_t()).label, 'No SLA');
      expect(
          resolutionSeg(_t({'sla_remaining_seconds': 500, 'sla_hold_started_at': '2026-10-27T10:00:00+05:30'})).label,
          'Paused — waiting on customer');
      final risk = resolutionSeg(_t({'sla_remaining_seconds': 3600, 'sla_deadline': '2026-10-27T13:00:00+05:30'}));
      expect(risk.label, endsWith(' · 1h 0m left'));
      expect(risk.tone, SlaTone.atRisk);
      final late = resolutionSeg(_t({'sla_remaining_seconds': -7200, 'sla_deadline': '2026-10-27T10:00:00+05:30'}));
      expect(late.label, startsWith('Overdue 2h 0m · was due '));
      expect(late.tone, SlaTone.breached);
      expect(resolutionSeg(_t({'sla_remaining_seconds': 200000})).tone, SlaTone.normal);
    });

    test('SLA target wording', () {
      expect(formatSlaTarget(1, 'hours'), '1 hour');
      expect(formatSlaTarget(24, 'hours'), '24 hours');
      expect(formatSlaTarget(7, 'days'), '7 days');
      expect(formatSlaTarget(null, 'days'), 'No SLA');
    });
  });

  group('detail mapping', () {
    test('hierarchy, files, replies and custom fields', () {
      final t = _t({
        'parent_issue': '22222222-2222-2222-2222-222222222222',
        'parent_reference': 'TKT-0001',
        'parent_subject': 'Parent',
        'child_count': 0,
        'attachments': [
          {'attachment_id': 'a1', 'name': 'log.txt', 'file': 'x', 'file_url': 'x?token=1', 'uploaded_by': {'name': 'Sufail Salim'}},
        ],
        'notes': [
          {'note_id': 'n1', 'content': 'internal'},
          {'note_id': 'n2', 'kind': 'reply', 'content': 'Hello', 'created_by': {'name': 'Ashish'}},
        ],
        'custom_fields': {'form.order_id': 'UAT-1', 'qty': 3},
        'sla_value': 7,
        'sla_unit': 'days',
      });
      final f = t.facts!;
      expect(f.isChild, isTrue);
      expect(f.parentReference, 'TKT-0001');
      expect(f.attachments.single.url, 'x?token=1');
      expect(f.attachments.single.uploadedBy, 'Sufail Salim');
      expect(f.replies.single.body, 'Hello');
      expect(f.customFields, {'form.order_id': 'UAT-1', 'qty': '3'});
      expect(formatSlaTarget(f.slaValue, f.slaUnit), '7 days');
    });

    test('linked task row', () {
      final task = TicketsRemoteDataSource.linkedTaskFromJson({
        'task_id': 't1',
        'subject': 'Fix it',
        'project_name': 'Portal',
        'status': 'uuid',
        'status_name': 'In Progress',
        'priority': 'High',
        'is_overdue': true,
      });
      expect(task.projectName, 'Portal');
      expect(task.status, 'In Progress');
      expect(task.isOverdue, isTrue);
    });
  });

  test('custom field labels', () {
    expect(customFieldLabel('form.order_id'), 'Order id');
    expect(customFieldLabel('customer-tier'), 'Customer tier');
  });

  test('billing row', () {
    String money(double v) => '₹${v.toStringAsFixed(0)}';
    expect(billingRowValue(_t(), money), isNull);
    expect(billingRowValue(_t({'billable': true, 'billable_amount': '2500.00'}), money), 'Billable · ₹2500');
    expect(billingRowValue(_t({'billable': true, 'billable_product': 'p'}), money), 'Billable · product');
  });

  test('hierarchy errors keep the webapp copy', () {
    AppError err(String code) => AppError(
          type: AppErrorType.validation,
          message: 'x',
          extra: {
            'error_codes': {'parent_issue': [code]},
          },
        );
    expect(hierarchyErrorCopy(err('parent_would_nest')),
        "That ticket already has children of its own, so it can't become a child.");
    expect(hierarchyErrorCopy(err('parent_depth_exceeded')),
        'That ticket is already a child of another ticket. Tickets can only nest two levels deep.');
    expect(hierarchyErrorCopy(err('parent_self_reference')), "A ticket can't be its own parent.");
  });

  test('assignee choices keep the current assignee', () {
    final out = assigneeChoices([(id: 'a', name: 'A')], currentId: 'z', currentName: 'Zed');
    expect(out.map((u) => u.id), ['z', 'a']);
    expect(assigneeChoices([(id: 'a', name: 'A')], currentId: 'a').length, 1);
  });
}
