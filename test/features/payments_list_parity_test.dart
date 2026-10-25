import 'package:clozrapp/features/crm/application/payments_list_view.dart';
import 'package:clozrapp/features/crm/domain/entities/invoice.dart';
import 'package:clozrapp/features/crm/domain/entities/payment.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/invoices_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/payments_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

/// CRM › Payments list parity with the webapp (CRM-PY-001…005, 010, 011, 038).
/// Rows are trimmed copies of the live dev payloads.
void main() {
  group('payMoney (PY-038)', () {
    test('full Indian grouping, paise only when non-zero, sign, null', () {
      expect(payMoney(1234567.5), '₹12,34,567.50');
      expect(payMoney(100), '₹100');
      expect(payMoney(-250), '-₹250');
      expect(payMoney(null), '—');
      expect(payMoney(74339), '₹74,339');
      expect(payMoney(53339.33), '₹53,339.33');
    });
  });

  group('plan rows (PY-002 / PY-003)', () {
    Invoice plan(Map<String, dynamic> extra) => invoiceFromApi({
          'payment_id': 'p-1',
          'quotation_number': 'QTN-1',
          'status': 'active',
          ...extra,
        })!;

    test('type labels match the webapp', () {
      expect(plan({'payment_type': 'lumpsum'}).type, 'Lump sum');
      expect(plan({'payment_type': 'subscription'}).type, 'Subscription');
      expect(plan({'payment_type': 'installment_even'}).type, 'Instalments – even split');
      expect(plan({'payment_type': 'installment_custom'}).type, 'Milestone-based');
      expect(planTypeLabel('some_new_type'), 'Some new type');
    });

    test('status split: any payment on an active plan is Partial', () {
      // QTN-00008: a subscription whose total_amount is ONE period, two paid.
      final sub = plan({
        'payment_type': 'subscription',
        'total_amount': '334998.00',
        'amount_paid': 729756.0,
        'amount_remaining': 385711.3,
      });
      expect(sub.status, 'partial');
      // QTN-00004: nothing paid.
      expect(plan({'total_amount': '86999.00', 'amount_paid': 0.0, 'amount_remaining': 86999.0}).status, 'unpaid');
      // QTN-00009: the server says completed even with GST still open.
      expect(
        plan({'status': 'completed', 'total_amount': '50000.00', 'amount_paid': 50000.0, 'amount_remaining': 7430.87}).status,
        'completed',
      );
      // Nothing left to settle completes it too (TDS-settled).
      expect(plan({'total_amount': '100.00', 'amount_paid': 90.0, 'amount_remaining': 0.0}).status, 'completed');
    });

    test('figures: incl. GST with the as-quoted line when it differs', () {
      final iv = plan({
        'payment_type': 'installment_even',
        'total_amount': '62999.00',
        'amount_paid': 20999.67,
        'amount_remaining': 45202.71,
        'total_incl_gst': '74339.00',
        'amount_due_incl_gst': '53339.33',
      });
      final f = planListFigures(iv);
      expect(payMoney(f.total), '₹74,339');
      expect(f.totalSub, 'As quoted ₹62,999');
      expect(payMoney(f.due), '₹53,339.33');
      expect(f.dueSub, 'As quoted ₹45,202.71');

      final same = planListFigures(plan({
        'total_amount': '110000.00',
        'amount_paid': 110000.0,
        'amount_remaining': 0.0,
        'total_incl_gst': '110000.00',
        'amount_due_incl_gst': '0.00',
      }));
      expect(same.totalSub, '');
      expect(same.dueSub, '');
    });

    test('a subscription lists its per-period charge and open periods', () {
      final iv = plan({
        'payment_type': 'subscription',
        'total_amount': '334998.00',
        'amount_due_incl_gst': '454518.00',
        'subscription': {
          'period_label': '10 days',
          'amount_per_period': '334998.00',
          'amount_per_period_incl_gst': '394758.00',
          'periods_scheduled': 3,
          'periods_paid': 2,
          'periods_open': 1,
          'open_ended': true,
        },
      });
      final f = planListFigures(iv);
      expect(payMoney(f.total), '₹3,94,758');
      expect(f.totalSub, 'per 10 days');
      expect(payMoney(f.due), '₹4,54,518');
      expect(f.dueSub, '1 period open');
      expect(planProgressText(iv), '2 of 3 scheduled periods paid · ongoing');
    });

    test('progress text: recurring, record counts, then percentage', () {
      final rec = plan({
        'payment_type': 'subscription',
        'recurring': {'periods_paid': 1, 'effective_term_periods': 12, 'ongoing': false},
      });
      expect(planProgressText(rec), '1 of 12 paid');
      final ongoing = plan({
        'recurring': {'periods_paid': 3, 'effective_term_periods': null},
      });
      expect(planProgressText(ongoing), '3 paid · ongoing');

      final even = plan({'total_amount': '300.00', 'amount_paid': 100.0, 'amount_remaining': 200.0});
      expect(planProgressText(even, counts: const PlanRecordCount(3, 2)), '2/3 settled');
      expect(planProgressText(even), '33% settled');
    });

    test('record counts: every record counts, settled = settlement_state paid', () {
      final rows = paymentsFromApiRows([
        {'record_id': 'a', 'payment': 'p-1', 'status': 'paid', 'settlement_state': 'partly_paid'},
        {'record_id': 'b', 'payment': 'p-1', 'status': 'paid', 'settlement_state': 'paid'},
        {'record_id': 'c', 'payment': 'p-1', 'status': 'pending'},
        {'record_id': 'd', 'payment': 'p-2', 'status': 'cancelled'},
      ]);
      final counts = planRecordCounts(rows);
      expect(counts['p-1']!.count, 3);
      expect(counts['p-1']!.settled, 1);
      expect(counts['p-2']!.count, 1);
    });

    test('lead-only plan is named after its lead (from the records)', () {
      final rows = paymentsFromApiRows([
        {'record_id': 'a', 'payment': 'p-9', 'customer_name': null, 'lead_name': 'Arjun Roy - Upselling 01'},
      ]);
      final leads = planLeadNames(rows);
      expect(planWho(null, leads['p-9']), (name: 'Arjun Roy - Upselling 01', isLead: true));
      expect(planWho('Manoj Nair', 'x'), (name: 'Manoj Nair', isLead: false));
      expect(planWho(null, null), (name: '—', isLead: false));
    });

    test('two plans of one quote (recurring split) get unique ids', () {
      final plans = invoicesFromApiRows([
        {'payment_id': 'one-time', 'quotation_number': 'QTN-00044', 'payment_type': 'lumpsum'},
        {'payment_id': 'recurring', 'quotation_number': 'QTN-00044', 'payment_type': 'subscription'},
        {'payment_id': 'solo', 'quotation_number': 'QTN-00042'},
      ]);
      expect(plans.map((p) => p.id), ['one-time', 'recurring', 'QTN-00042']);
      expect(plans.first.quoteId, 'QTN-00044');
      expect(plans.first.paymentType, 'lumpsum');
    });

    test('counter wording', () {
      expect(planCountLabel(1), '1 payment plan');
      expect(planCountLabel(6), '6 payment plans');
      expect(paymentCountLabel(0), '0 payments');
      expect(paymentCountLabel(1), '1 payment');
    });
  });

  group('payment record rows (PY-005)', () {
    final paidPartly = paymentRecordFromApi({
      'record_id': 'r-1',
      'installment_number': 1,
      'payment': 'p-2',
      'quotation_number': 'QTN-00002',
      'customer_name': 'Arjun Roy',
      'lead_name': 'Arjun Roy',
      'amount_expected': '20999.67',
      'amount_paid': '20999.67',
      'due_date': '2026-10-05',
      'paid_date': '2026-10-04',
      'status': 'paid',
      'notes': 'Installment 1 of 3',
      'payment_method': 'bank_transfer',
      'settlement_state': 'partly_paid',
      'amount_due_incl_gst': '24780.00',
      'amount_due_basis': 'ESTIMATE',
      'balance_due': '3780.33',
    })!;

    test('settlement pill, incl.-GST figure, hint, as-quoted, paid date', () {
      expect(settlementPill(paidPartly), (label: 'Partly paid', tone: PayTone.warning));
      expect(payMoney(paidPartly.amountDueInclGst), '₹24,780');
      expect(amountDueHint(paidPartly), 'incl. GST · estimate');
      expect(quotedAmountNote(paidPartly), 'As quoted ₹20,999.67');
      expect(paidPartly.date, '04-Oct-2026');
      expect(paymentSubLine(paidPartly), 'QTN-00002 · Installment 1 of 3');
      expect(paymentWho(paidPartly), (name: 'Arjun Roy', isLead: false));
    });

    test('overdue pending stays red "Pending"; due pending amber', () {
      final overdue = paymentRecordFromApi({
        'record_id': 'r-2',
        'status': 'overdue',
        'due_date': '2026-10-05',
        'settlement_state': 'pending',
      })!;
      expect(settlementPill(overdue), (label: 'Pending', tone: PayTone.danger));
      expect(overdue.date, 'Overdue 05-Oct-2026');
      final due = paymentRecordFromApi({'record_id': 'r-3', 'status': 'pending', 'due_date': '2026-11-04'})!;
      expect(due.status, 'due');
      expect(settlementPill(due), (label: 'Pending', tone: PayTone.warning));
      expect(due.date, 'Due 04-Nov-2026');
      final paid = paymentRecordFromApi({'record_id': 'r-4', 'status': 'paid', 'settlement_state': 'paid'})!;
      expect(settlementPill(paid), (label: 'Paid', tone: PayTone.success));
      final cancelled = paymentRecordFromApi({'record_id': 'r-5', 'status': 'cancelled'})!;
      expect(settlementPill(cancelled), (label: 'Cancelled', tone: PayTone.muted));
    });

    test('lead-only record shows the lead with a badge; linked one says so', () {
      final lead = paymentRecordFromApi({
        'record_id': 'r-6',
        'quotation_number': 'QTN-00009',
        'customer_name': null,
        'lead_name': 'UAT Pay Even',
        'notes': '',
        'installment_number': 2,
        'linked_document_id': 'doc-1',
      })!;
      expect(paymentWho(lead), (name: 'UAT Pay Even', isLead: true));
      expect(paymentSubLine(lead), 'QTN-00009 · Installment 2 · Linked to tax invoice');
    });

    test('as-quoted basis: no GST on top, no as-quoted line', () {
      final r = paymentRecordFromApi({
        'record_id': 'r-7',
        'amount_expected': '110000.00',
        'amount_due_incl_gst': '110000.00',
        'amount_due_basis': 'AS_QUOTED',
      })!;
      expect(amountDueHint(r), 'as quoted');
      expect(quotedAmountNote(r), '');
    });

    test('older backend: incl. GST falls back to gross, then expected', () {
      final r = paymentRecordFromApi({'record_id': 'r-8', 'amount_expected': '500.00', 'amount_due_gross': '590.00'})!;
      expect(r.amountDueInclGst, 590);
      expect(amountDueHint(r), 'incl. GST');
      final bare = paymentRecordFromApi({'record_id': 'r-9', 'amount_expected': '500.00'})!;
      expect(bare.amountDueInclGst, 500);
      expect(amountDueHint(bare), '');
    });

    test('chips: Due and Scheduled both hold the pending records', () {
      final rows = paymentsFromApiRows([
        {'record_id': 'a', 'status': 'paid'},
        {'record_id': 'b', 'status': 'pending'},
        {'record_id': 'c', 'status': 'pending'},
        {'record_id': 'd', 'status': 'overdue'},
        {'record_id': 'e', 'status': 'cancelled'},
      ]);
      expect(paymentChipCount(rows, 'all'), 5);
      expect(paymentChipCount(rows, 'paid'), 1);
      expect(paymentChipCount(rows, 'due'), 2);
      expect(paymentChipCount(rows, 'scheduled'), 2);
      expect(paymentChipCount(rows, 'overdue'), 1);
    });

    test('auto-debit method label', () {
      expect(paymentMethodDisplay('auto_debit'), 'Auto-debit');
    });
  });

  group('delete eligibility (PY-011)', () {
    Payment rec(Map<String, dynamic> extra) =>
        paymentRecordFromApi({'record_id': 'r', 'status': 'pending', ...extra})!;

    test('only an unpaid, uninvoiced record on a milestone plan, with permission', () {
      final open = rec({});
      expect(canDeletePaymentRecord(open, planType: 'installment_custom', hasDeletePermission: true), isTrue);
      expect(canDeletePaymentRecord(open, planType: 'installment_custom', hasDeletePermission: false), isFalse);
      expect(canDeletePaymentRecord(open, planType: 'installment_even', hasDeletePermission: true), isFalse);
      expect(canDeletePaymentRecord(open, planType: null, hasDeletePermission: true), isFalse);
      expect(
        canDeletePaymentRecord(rec({'status': 'paid', 'settlement_state': 'paid'}),
            planType: 'installment_custom', hasDeletePermission: true),
        isFalse,
      );
      expect(
        canDeletePaymentRecord(rec({'linked_document_id': 'doc'}), planType: 'installment_custom', hasDeletePermission: true),
        isFalse,
      );
      expect(
        canDeletePaymentRecord(rec({'settlement_state': 'partly_paid', 'amount_paid': '10.00'}),
            planType: 'installment_custom', hasDeletePermission: true),
        isFalse,
      );
    });

    test('confirm copy is the webapp\'s', () {
      expect(deleteRecordTitle, 'Delete this payment record?');
      expect(
        deleteRecordBody,
        "Only records on milestone-type payment plans can be deleted, and never a paid or invoiced one. "
        "The plan's totals are recalculated afterwards. This cannot be undone.",
      );
      expect(deleteRecordToast, 'Payment record deleted');
    });
  });
}
