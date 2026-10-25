import 'package:clozrapp/features/crm/application/payment_plan/payment_plan_detail.dart';
import 'package:clozrapp/features/crm/application/payment_plan/payment_plan_rules.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _record({
  String id = 'r1',
  int n = 1,
  String status = 'pending',
  String settlement = 'pending',
  String expected = '3333.05',
  String dueIncl = '3933.00',
  String paid = '0.00',
  String notes = 'Installment 1 of 3',
  String? blocked,
  String? linked,
  String due = '2026-11-04',
  String? paidDate,
  String method = '',
}) =>
    {
      'record_id': id,
      'installment_number': n,
      'payment': 'plan-1',
      'quotation_number': 'QTN-00041',
      'amount_expected': expected,
      'amount_paid': paid,
      'amount_due_incl_gst': dueIncl,
      'amount_due_basis': 'ESTIMATE',
      'status': status,
      'settlement_state': settlement,
      'notes': notes,
      'due_date': due,
      'paid_date': paidDate,
      'payment_method': method,
      'invoice_blocked_reason': blocked,
      'linked_document_id': linked,
      'record_summary': {'state': 'INACTIVE', 'document': null, 'receipt': null, 'adjustments': null},
    };

PlanDetail _plan({
  String type = 'installment_even',
  String status = 'active',
  Object? customer = const {'customer_id': 'c1', 'name': 'Arjun Roy'},
  List<Map<String, dynamic>>? records,
  List<Map<String, dynamic>> attention = const [],
  bool editable = false,
  String total = '62999.00',
  Object paid = 20999.67,
  Object remaining = 45202.71,
  Map<String, dynamic>? recurring,
  Map<String, dynamic>? subscription,
  Map<String, dynamic>? split,
  String? scope,
  String? unscheduled,
  String? quoted,
}) =>
    PlanDetail.fromJson({
      'payment_id': 'plan-1',
      'quotation': 'q-1',
      'quotation_number': 'QTN-00002',
      'customer': customer,
      'payment_type': type,
      'status': status,
      'total_amount': total,
      'amount_paid': paid,
      'amount_remaining': remaining,
      'total_incl_gst': '74339.00',
      'amount_due_incl_gst': '53339.33',
      'advance_received': '20999.67',
      'invoiced_total': '0',
      'num_installments': 3,
      'billing_period_days': 30,
      'needs_attention': attention,
      'schedule_editable': editable,
      'recurring': recurring,
      'subscription': subscription,
      'charge_split': split,
      'charge_scope': scope,
      'unscheduled_incl_gst': unscheduled,
      'quoted_total_incl_gst': quoted,
      'owner': {'user_id': 'u1', 'name': 'Ashish Nexotech', 'email': 'ashish.kurian@nexotech.cc'},
      'records': records ??
          [
            _record(id: 'r1', status: 'paid', settlement: 'paid', paid: '20999.67', paidDate: '2026-10-04', method: 'bank_transfer'),
            _record(id: 'r2', n: 2, notes: 'Installment 2 of 3'),
            _record(id: 'r3', n: 3, notes: 'Installment 3 of 3'),
          ],
    });

void main() {
  group('money (PY-038)', () {
    test('full Indian format, paise only when non-zero', () {
      expect(planMoney(1234567.5), '₹12,34,567.50');
      expect(planMoney(100), '₹100');
      expect(planMoney(-250), '-₹250');
      expect(planMoney(null), '—');
      expect(planMoney(74339), '₹74,339');
    });
  });

  group('header (PY-025 / PY-033)', () {
    test('type label + progress counts fully settled records', () {
      final p = _plan();
      expect(planHeaderType(p), 'Instalments – even split');
      expect(planProgressLabel(p), '1 of 3 settled');
      expect(planStatusKey(p), 'partial');
    });

    test('a partly-paid record is not counted as settled', () {
      final p = _plan(records: [_record(status: 'paid', settlement: 'partly_paid'), _record(id: 'r2')]);
      expect(planProgressLabel(p), '0 of 2 settled');
    });

    test('subscription uses the server header and reads Partial, not Unpaid', () {
      final p = _plan(
        type: 'subscription',
        total: '334998.00',
        paid: 729756.0,
        remaining: 385711.3,
        subscription: {
          'period_label': '10 days',
          'amount_per_period': '334998.00',
          'amount_per_period_incl_gst': '394758.00',
          'periods_open': 1,
          'header': '₹3,94,758 / 10 days (incl. GST) · next due 25-Oct · 2 paid',
        },
      );
      expect(planStatusKey(p), 'partial');
      expect(planProgressLabel(p), startsWith('₹3,94,758 / 10 days'));
      final kpis = planKpis(p, accountingActive: false);
      expect(kpis.first.label, 'Per period (incl. GST)');
      expect(kpis.first.sub, 'Every 10 days · as quoted ₹3,34,998');
      expect(kpis.last.sub, '1 period open');
    });

    test('completed server status wins', () {
      expect(planStatusKey(_plan(status: 'completed')), 'completed');
    });

    test('KPIs incl. GST with as-quoted sub-lines; accounting adds Advance / Invoiced', () {
      final p = _plan();
      final off = planKpis(p, accountingActive: false);
      expect(off.map((k) => k.label), ['Total (incl. GST)', 'Paid', 'Amount due (incl. GST)']);
      expect(planMoney(off[0].value), '₹74,339');
      expect(off[0].sub, 'As quoted ₹62,999');
      expect(planMoney(off[2].value), '₹53,339.33');
      final on = planKpis(p, accountingActive: true);
      expect(on.map((k) => k.label), ['Total (incl. GST)', 'Advance received', 'Invoiced', 'Amount due (incl. GST)']);
    });

    test('row label / date / pill', () {
      final p = _plan();
      final r1 = p.records[0];
      final r2 = p.records[1];
      expect(r2.displayLabel, 'Installment 2 of 3');
      expect(recordRowDate(r1), '4 Oct 2026');
      expect(recordRowDate(r2), 'Due 4 Nov 2026');
      expect(recordPillLabel(r1), 'Paid');
      expect(recordPillLabel(r2), 'Pending');
      expect(paymentMethodLabel(r1.method), 'Bank transfer');
      expect(amountDueHint(r2), 'incl. GST · estimate');
      expect(quotedAmountNote(r2), 'As quoted ₹3,333.05');
      expect(PlanRecord.fromJson(_record(notes: '', n: 4)).displayLabel, 'Installment 4');
    });
  });

  group('record payment / settle (PY-026 / PY-033)', () {
    test('Record payment hidden on a completed plan or without create', () {
      expect(canRecordPayment(_plan(), canCreate: true), isTrue);
      expect(canRecordPayment(_plan(), canCreate: false), isFalse);
      expect(canRecordPayment(_plan(status: 'completed'), canCreate: true), isFalse);
    });

    test('Settle only on open rows', () {
      final p = _plan(records: [
        _record(status: 'paid', settlement: 'paid'),
        _record(id: 'r2', status: 'cancelled'),
        _record(id: 'r3', status: 'overdue'),
      ]);
      expect(p.records.map((r) => canSettleRecord(r, canRecord: true)), [false, false, true]);
      expect(canSettleRecord(p.records[2], canRecord: false), isFalse);
    });
  });

  group('re-split (PY-027)', () {
    test('validation wording', () {
      for (final c in ['0', '61', '', 'x']) {
        expect(validateScheduleDraft(ScheduleDraft(count: c, periodDays: '30', firstDueDate: ''))['count'],
            'Enter 1 to 60 instalments.');
      }
      for (final d in ['0', '367']) {
        expect(validateScheduleDraft(ScheduleDraft(count: '3', periodDays: d, firstDueDate: ''))['periodDays'],
            'Enter 1 to 366 days.');
      }
      expect(validateScheduleDraft(const ScheduleDraft(count: '60', periodDays: '366', firstDueDate: '')), isEmpty);
    });

    test('preview text of an equal split', () {
      expect(previewSplit(10000, 3), [3333, 3333, 3334]);
      expect(previewSplit(36000, 3), [12000, 12000, 12000]);
      expect(
        schedulePreviewText(10000, const ScheduleDraft(count: '3', periodDays: '30', firstDueDate: '')),
        'About 2 × ₹3,333 + ₹3,334 (incl. GST). The exact amounts add up to the plan total; the last instalment takes the remainder.',
      );
      expect(schedulePreviewText(10000, const ScheduleDraft(count: '1', periodDays: '30', firstDueDate: '')), '');
    });

    test('body, initial draft, visibility and toast', () {
      expect(scheduleBody(const ScheduleDraft(count: '3', periodDays: '30', firstDueDate: '2026-11-01')),
          {'num_installments': 3, 'billing_period_days': 30, 'first_due_date': '2026-11-01'});
      final lump = _plan(type: 'lumpsum', editable: true, records: [_record(due: '2026-10-24')]);
      final d = initialScheduleDraft(lump);
      expect([d.count, d.periodDays, d.firstDueDate], ['3', '30', '2026-10-24']);
      expect(canChooseInstalments(lump), isTrue);
      expect(canChooseInstalments(_plan(editable: false)), isFalse);
      expect(canChooseInstalments(_plan(type: 'subscription', editable: true)), isFalse);
      expect(scheduleSavedToast(lump), 'Plan set to a single payment');
      expect(scheduleSavedToast(_plan()), 'Plan split into 3 instalments');
    });
  });

  group('milestones (PY-028)', () {
    test('validation wording', () {
      Map<String, String> v({String label = 'Design', bool percent = false, String amount = '100', String due = '2026-11-01'}) =>
          validateMilestone(label: label, percent: percent, amount: amount, dueDate: due, base: 100000);
      expect(v(label: '  ')['label'], 'Name the milestone (e.g. Design sign-off).');
      expect(v(label: 'x' * 121)['label'], 'Keep it under 120 characters.');
      expect(v(label: 'x' * 120)['label'], isNull);
      expect(v(amount: '0')['amount'], 'Enter an amount greater than 0.');
      expect(v(percent: true, amount: '150')['amount'], 'Enter a percentage between 0 and 100.');
      expect(v(due: '')['dueDate'], 'Pick the date this milestone falls due.');
      expect(v(percent: true, amount: '40'), isEmpty);
    });

    test('amount, note, intro, body and toast', () {
      expect(milestoneAmount(percent: true, amount: '40', base: 100000), 40000);
      expect(milestoneAmount(percent: false, amount: '₹25,000.5', base: 0), 25000.5);
      expect(milestoneAmountNote(percent: true, amount: '40', base: 100000, unscheduled: 100000),
          '₹40,000 incl. GST · ₹1,00,000 of the quote not yet scheduled');
      expect(milestoneAmountNote(percent: false, amount: '120000', base: 100000, unscheduled: 100000),
          '₹20,000 more than the ₹1,00,000 not yet scheduled');
      expect(milestoneIntro('QTN-00043', 100000),
          'A milestone is scheduled on QTN-00043 with its own payment follow-up on its due date. Quote total ₹1,00,000 incl. GST.');
      expect(milestoneBody(planId: 'p', label: ' Design sign-off ', amountInclGst: 943.905, dueDate: '2026-11-01'), {
        'payment': 'p',
        'amount_incl_gst': '943.91',
        'amount_paid': '0',
        'status': 'pending',
        'due_date': '2026-11-01',
        'notes': 'Design sign-off',
      });
      expect(milestoneAddedToast(40000), 'Milestone added — ₹40,000 due, follow-up created');
      final m = _plan(type: 'installment_custom', records: const [], quoted: '11800.00');
      expect(canAddMilestones(m), isTrue);
      expect(milestoneBaseTotal(m), 11800);
      expect(canAddMilestones(_plan(type: 'installment_custom', status: 'cancelled')), isFalse);
      expect(canAddMilestones(_plan()), isFalse);
    });
  });

  group('recurring (PY-029)', () {
    final p = _plan(
      type: 'subscription',
      scope: 'recurring',
      recurring: {
        'period_label': 'month',
        'effective_term_periods': 12,
        'periods_paid': 1,
        'periods_elapsed': 2,
        'progress_pct': 50,
        'next_due_date': '2026-10-24',
        'first_period_start': '2026-10-24',
        'next_period_start': '2026-12-24',
        'can_stop': true,
        'header': '₹2,360 / month · next due 24-Oct · 1 of 12 paid',
      },
      split: {
        'one_time': {'payment_id': 'one-time-plan'},
        'recurring': {'payment_id': 'plan-1'},
        'label': '₹11,800 one-time + ₹2,360 / month',
      },
    );

    test('header, default stop date, link to the other plan', () {
      expect(planHeaderType(p), 'Recurring');
      expect(planProgressLabel(p), '₹2,360 / month · next due 24-Oct · 1 of 12 paid');
      expect(defaultStopFrom(p.recurring!), '2026-12-24');
      expect(p.recurring!.periodsPaidLabel, '1 of 12 paid');
      expect(recurringProgressText(p.recurring!), '1 of 2 periods due so far paid (50%).');
      expect(chargeSplitLink(p), ('one-time-plan', 'Open the one-time plan'));
      expect(p.chargeSplit!.label, '₹11,800 one-time + ₹2,360 / month');
      expect(stopRecurringBody('24 Dec 2026'), startsWith('No period starting on or after 24 Dec 2026 will be billed.'));
    });

    test('one-time side links to the recurring schedule', () {
      final one = _plan(type: 'lumpsum', scope: 'one_time', split: {
        'one_time': {'payment_id': 'plan-1'},
        'recurring': {'payment_id': 'rec-plan'},
        'label': 'x',
      });
      expect(planHeaderType(one), 'One-time part');
      expect(chargeSplitLink(one), ('rec-plan', 'Open the recurring schedule'));
    });
  });

  group('needs attention (PY-032)', () {
    test('server items win', () {
      final p = _plan(attention: [
        {'code': 'MILESTONES_REQUIRED', 'message': 'No milestones yet.', 'record_ids': []},
      ]);
      expect(effectiveNeedsAttention(p).single.code, milestonesRequired);
      expect(attentionText(effectiveNeedsAttention(p).single), 'No milestones yet.');
    });

    test('nothing is derived when the server sends no items (web parity)', () {
      expect(effectiveNeedsAttention(_plan(customer: null, records: [_record(id: 'b')])), isEmpty);
      expect(effectiveNeedsAttention(_plan(type: 'installment_custom', records: const [])), isEmpty);
    });

    test('nothing on a customer plan with milestones', () {
      expect(effectiveNeedsAttention(_plan()), isEmpty);
    });

    test('record-level block reason tags the row', () {
      final r = PlanRecord.fromJson(_record(blocked: 'CUSTOMER_REQUIRED'));
      expect(isBlockedForCustomer(r, const []), isTrue);
    });
  });

  group('record detail (PY-035 / PY-011)', () {
    test('activity wording', () {
      final paid = PlanRecord.fromJson(_record(status: 'paid', settlement: 'paid', paidDate: '2026-10-04'));
      expect(recordActivity(paid), [
        ('Payment received', '4 Oct 2026'),
        ('Payment plan QTN-00041 created', 'System · On creation'),
      ]);
      final open = PlanRecord.fromJson(_record());
      expect(recordActivity(open).first.$1, 'Payment pending');
    });

    test('delete eligibility', () {
      final open = PlanRecord.fromJson(_record());
      expect(canDeleteRecord(planType: 'installment_custom', record: open, canDelete: true), isTrue);
      expect(canDeleteRecord(planType: 'installment_custom', record: open, canDelete: false), isFalse);
      expect(canDeleteRecord(planType: 'installment_even', record: open, canDelete: true), isFalse);
      final paid = PlanRecord.fromJson(_record(status: 'paid', settlement: 'paid'));
      expect(canDeleteRecord(planType: 'installment_custom', record: paid, canDelete: true), isFalse);
      final linked = PlanRecord.fromJson(_record(linked: 'doc-1'));
      expect(canDeleteRecord(planType: 'installment_custom', record: linked, canDelete: true), isFalse);
    });

    test('owner / customer parsing', () {
      final p = _plan(customer: null);
      expect(p.ownerName, 'Ashish Nexotech');
      expect(p.ownerEmail, 'ashish.kurian@nexotech.cc');
      expect(p.customerId, '');
      expect(isUuidLike('dffdbf07-9604-4c25-bae9-170a4d8d525c'), isTrue);
      expect(isUuidLike('QTN-00002'), isFalse);
    });
  });
}
