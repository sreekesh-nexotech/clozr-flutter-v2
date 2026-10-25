import 'package:clozrapp/features/crm/application/customer_activity_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('payments (webapp customerPayments.ts)', () {
    // Live shape: Arjun Roy (CUST-0002), plan from QTN-00002, instalment 1 part-paid.
    final payments = [
      {
        'payment_id': 'p1',
        'quotation_number': 'QTN-00002',
        'payment_type': 'installment_even',
        'total_amount': '62999.00',
        'amount_paid': 20999.67,
        'amount_remaining': 45202.71,
        'total_incl_gst': '74339.00',
        'amount_due_incl_gst': '53339.33',
        'amount_remaining_incl_gst': '53339.33',
        'status': 'active',
        'subscription': null,
        'unscheduled_incl_gst': null,
      }
    ];
    final records = [
      {
        'record_id': 'r3', 'payment': 'p1', 'installment_number': 3, 'amount_expected': '20999.66',
        'due_date': '2026-12-04', 'payment_method': '', 'status': 'pending', 'notes': 'Installment 3 of 3',
        'amount_due_incl_gst': '24779.00', 'amount_paid': '0.00', 'balance_due': '24779.00', 'settlement_state': 'pending',
      },
      {
        'record_id': 'r1', 'payment': 'p1', 'installment_number': 1, 'amount_expected': '20999.67',
        'due_date': '2026-10-05', 'payment_method': 'bank_transfer', 'status': 'paid', 'notes': 'Installment 1 of 3',
        'amount_due_incl_gst': '24780.00', 'amount_paid': '20999.67', 'balance_due': '3780.33', 'settlement_state': 'partly_paid',
      },
      {
        'record_id': 'r2', 'invoice_id': 'p1', 'installment_number': 2, 'amount_expected': '20999.67',
        'due_date': '2026-11-04', 'payment_method': '', 'status': 'overdue', 'notes': '',
        'amount_due_incl_gst': '24780.00', 'amount_paid': '0.00', 'balance_due': '24780.00', 'settlement_state': 'pending',
      },
      {'record_id': 'orphan', 'installment_number': 1},
    ];

    test('groups records under their plan, sorted by number', () {
      final plans = customerPaymentsFromRows(payments, records);
      expect(plans, hasLength(1));
      final p = plans.single;
      expect([for (final r in p.records) r.id], ['r1', 'r2', 'r3']);
      expect(p.records[1].label, 'Installment 2'); // no notes → fallback label
      expect(paymentPlanTitle(p), 'Payment plan #QTN-00002 (from accepted quote)');
      expect(paymentPlanPill(p).label, 'Due');
    });

    test('stats on the incl.-GST basis', () {
      final p = customerPaymentsFromRows(payments, records).single;
      final stats = paymentPlanStats(p);
      expect([for (final s in stats) s.label], ['Total (incl. GST)', 'Paid', 'Balance due (incl. GST)']);
      expect(stats[0].value, 74339);
      expect(stats[1].value, closeTo(20999.67, 0.001));
      expect(stats[2].value, closeTo(53339.33, 0.001));
      expect(activityMoney(stats[0].value), '₹74,339');
      expect(activityMoney(stats[1].value), '₹20,999.67');
    });

    test('instalment rows: share, status, amount, meta', () {
      final p = customerPaymentsFromRows(payments, records).single;
      final rows = paymentPlanRows(p);
      expect(rows[0].title, 'Installment 1 of 3 · 33%');
      expect(rows[0].statusLabel, 'Partly paid');
      expect(rows[0].note, '₹20,999.67 paid · ₹3,780.33 due');
      expect(rows[0].amount, 24780);
      expect(rows[1].statusLabel, 'Overdue');
      expect(rows[2].statusLabel, 'Due');
      expect(paymentRowMeta(p, rows[0]),
          '5 Oct 2026 · Bank transfer · Instalments – even split · ₹20,999.67 paid · ₹3,780.33 due');
    });

    test('cancelled plan: Not collected, cancelled rows kept', () {
      final p = customerPaymentsFromRows([
        {...payments.single, 'status': 'cancelled'}
      ], [
        {...records[1], 'status': 'cancelled'},
        records[0],
      ]).single;
      expect(paymentPlanPill(p).label, 'Cancelled');
      expect(paymentPlanStats(p).last.label, 'Not collected (incl. GST)');
      final rows = paymentPlanRows(p);
      expect(rows.first.statusLabel, 'Cancelled');
      expect(rows.first.cancelled, isTrue);
    });

    test('completed plan pill is Paid; subscription per-period label', () {
      final p = customerPaymentsFromRows([
        {
          ...payments.single,
          'status': 'completed',
          'subscription': {'period_label': 'month', 'amount_per_period_incl_gst': '2832', 'header': 'h'},
        }
      ], const []).single;
      expect(paymentPlanPill(p).label, 'Paid');
      expect(paymentPlanStats(p).first.label, 'Per month (incl. GST)');
      expect(paymentPlanNote(p), 'h');
    });

    test('older backend without incl.-GST figures', () {
      final p = customerPaymentsFromRows([
        {'payment_id': 'x', 'total_amount': '1000', 'amount_paid': '400', 'status': 'active'}
      ], const []).single;
      expect([for (final s in paymentPlanStats(p)) s.label], ['Plan total', 'Paid', 'Balance due']);
      expect(paymentPlanStats(p).last.value, 600);
      expect(paymentPlanTitle(p), 'Payment plan');
    });
  });

  group('call log validation (AddCustomerCallLogModal)', () {
    test('From and To required', () {
      expect(validateCustomerCallLog(from: '', to: ''), 'From and To numbers are required.');
      expect(validateCustomerCallLog(from: '+911', to: '  '), 'From and To numbers are required.');
      expect(validateCustomerCallLog(from: '+911', to: '+912'), isNull);
    });

    test('duration must be HH:MM:SS when given', () {
      expect(validateCustomerCallLog(from: 'a', to: 'b', duration: '00:05:30'), isNull);
      expect(validateCustomerCallLog(from: 'a', to: 'b', duration: '5:30'), callLogDurationInvalid);
      expect(validateCustomerCallLog(from: 'a', to: 'b', duration: '00:61:00'), callLogDurationInvalid);
    });

    test('body is linked to the customer', () {
      final body = customerCallLogBody(
          customerId: 'c1', from: ' +911 ', to: '+912', direction: 'Outgoing', medium: 'Manual', duration: '00:05:30');
      expect(body, {
        'from_number': '+911',
        'to_number': '+912',
        'type': 'Outgoing',
        'telephony_medium': 'Manual',
        'duration': '00:05:30',
        'related_to': 'customer',
        'related_to_id': 'c1',
      });
      expect(
          customerCallLogBody(customerId: 'c1', from: 'a', to: 'b', direction: 'Incoming', medium: 'Exotel')
              .containsKey('duration'),
          isFalse);
    });

    test('call row view', () {
      final row = CustomerCallRow.fromJson({
        'crm_call_log_id': 'x',
        'type': 'Outgoing',
        'telephony_medium': 'Manual',
        'duration': '00:05:30',
        'start_time': '2026-10-24T08:00:00Z',
        'related_to_model': 'lead',
        'related_to_object_id': 'L1',
      });
      expect(row.isOutgoing, isTrue);
      expect(row.metaLine(now: DateTime.utc(2026, 10, 24, 10)), '00:05:30 · 2h ago');
      expect(leadHistoryTag(parentModel: row.parentModel, parentId: row.parentId, customerId: 'C', leadRefs: {'L1': 'LD-0021'}),
          'From lead LD-0021');
    });
  });

  group('history and note tags', () {
    test('own rows are untagged', () {
      expect(leadHistoryTag(parentModel: 'customer', parentId: 'C', customerId: 'C'), isNull);
      expect(relatedParentOf({
        'related_to': {'model': 'lead', 'id': 'L1', 'reference': 'LD-1'}
      }), (model: 'lead', id: 'L1', reference: 'LD-1'));
    });

    test('note sources', () {
      expect(noteSourceTag({'kind': 'customer', 'id': 'C'}, 'C'), isNull);
      expect(noteSourceTag({'kind': 'lead', 'id': 'L', 'reference': 'LD-0021'}, 'C'),
          (text: 'From lead LD-0021', readOnly: true));
      expect(noteSourceTag({'kind': 'task', 'id': 'T', 'label': 'Call back'}, 'C'),
          (text: 'Task · Call back', readOnly: false));
    });

    test('task due badge', () {
      final now = DateTime(2026, 10, 24, 15);
      expect(taskDueBadge(due: DateTime(2026, 10, 23), done: false, now: now), 'Overdue');
      expect(taskDueBadge(due: DateTime(2026, 10, 24), done: false, now: now), 'Today');
      expect(taskDueBadge(due: DateTime(2026, 10, 25), done: false, now: now), 'Upcoming');
      expect(taskDueBadge(due: DateTime(2026, 10, 1), done: true, now: now), 'Done');
      expect(taskDueBadge(due: null, done: false, now: now), isNull);
    });
  });

  test('opportunities from linked_leads', () {
    final leads = CustomerLinkedLead.listFrom([
      {
        'lead_id': 'L1',
        'lead_name': 'Manoj Nair',
        'reference': 'LD-0012',
        'is_upsell': false,
        'is_converted': true,
        'relation': 'source',
        'status_name': 'Won',
        'status_color': '#10B981',
        'lead_value': '334998.00',
        'quotes_count': 1,
        'accepted_quote': {'quotation_number': 'QTN-00008', 'grand_total': '394758.00'},
        'owner': {'name': 'Sufail Salim'},
        'created_at': '2026-10-04T15:17:37+05:30',
        'converted_on': '2026-10-05T11:42:22+05:30',
      },
      {'lead_id': 'L2', 'lead_name': 'Upsell', 'relation': 'upsell', 'quotes_count': 0},
      'junk',
    ]);
    expect(leads, hasLength(2));
    expect(leads[0].isSource, isTrue);
    expect(leads[0].quotesLine, '1 quote · QTN-00008 accepted (₹3,94,758 incl. GST)');
    expect(leads[0].metaLine, contains('Sufail Salim · 1 quote'));
    expect(leads[0].metaLine, contains('Opened 4 Oct 2026'));
    expect(leads[1].isSource, isFalse);
    expect(leads[1].quotesLine, '0 quotes');
  });
}
