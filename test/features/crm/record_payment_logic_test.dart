import 'package:clozrapp/features/crm/application/record_payment/record_payment_logic.dart';
import 'package:clozrapp/features/crm/application/record_payment/record_payment_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('rupees: paise only when present, Indian grouping', () {
      expect(rupees(10000), '₹10,000');
      expect(rupees(1234567.5), '₹12,34,567.50');
      expect(rupees(100), '₹100');
      expect(rupees(-250), '-₹250');
    });

    test('amountSeed', () {
      expect(amountSeed(3933), '3933');
      expect(amountSeed(3932.5), '3932.50');
      expect(amountSeed(0), '');
    });
  });

  group('settle amount (CRM-PY-014 / 018)', () {
    test('empty = full open balance', () {
      final r = validateSettleAmount(raw: '', balance: 10000);
      expect(r.ok, isTrue);
      expect(r.amountPaid, 10000);
    });

    test('partial is allowed', () {
      final r = validateSettleAmount(raw: '4000', balance: 10000);
      expect(r.ok, isTrue);
      expect(r.amountPaid, 4000);
    });

    test('more than the open balance is refused', () {
      expect(validateSettleAmount(raw: '7000', balance: 6000).error,
          'Amount cannot exceed the open balance of ₹6,000');
    });

    test('0 and negative are invalid', () {
      expect(validateSettleAmount(raw: '0', balance: 6000).error, 'Enter a valid amount');
      expect(validateSettleAmount(raw: '-5', balance: 6000).error, 'Enter a valid amount');
      expect(validateSettleAmount(raw: 'abc', balance: 6000).error, 'Enter a valid amount');
    });

    test('cash sent = owed − deductions', () {
      final r = validateSettleAmount(raw: '', balance: 10000, tds: 1000, bankCharge: 50);
      expect(r.amountPaid, 8950);
      expect(r.owed, 10000);
    });

    test('deductions cannot cover the whole installment', () {
      expect(validateSettleAmount(raw: '1000', balance: 10000, tds: 1000).error,
          'Deductions cannot cover the whole installment');
    });

    test('live note', () {
      expect(deductionsNote(1000, 50), 'Settles as cash received + ₹1,000 TDS + ₹50 bank charge.');
      expect(deductionsNote(0, 0), isNull);
      expect(deductionInput('-5'), 0);
      expect(deductionInput('1,000'), 1000);
    });
  });

  test('ad-hoc amount', () {
    expect(validateAdhocAmount(''), 'Enter a valid amount');
    expect(validateAdhocAmount('0'), 'Enter a valid amount');
    expect(validateAdhocAmount('2500'), isNull);
    expect(validateAdhocAmount('100', tds: 100), 'Deductions cannot cover the whole amount');
  });

  test('payment date cannot be in the future (CRM-PY-015)', () {
    final today = DateTime(2026, 10, 24, 15);
    expect(paymentDateError(DateTime(2026, 10, 24, 23), today), isNull);
    expect(paymentDateError(DateTime(2026, 10, 1), today), isNull);
    expect(paymentDateError(DateTime(2026, 10, 25), today), 'The payment date cannot be in the future.');
  });

  test('methods match the webapp, Bank transfer first (CRM-PY-016)', () {
    expect([for (final m in recordPayMethods) m.label], ['Bank transfer', 'UPI', 'Card', 'Cash', 'Cheque', 'Auto-debit']);
    expect(defaultPayMethodCode, 'bank_transfer');
    expect(recordPayMethods.last.code, 'auto_debit');
  });

  group('ad-hoc eligibility (CRM-PY-017)', () {
    test('milestone plans only', () {
      expect(adhocAllowedFor('installment_custom'), isTrue);
      expect(adhocAllowedFor('installment_even'), isFalse);
      expect(adhocAllowedFor('lumpsum'), isFalse);
      expect(adhocAllowedFor(null), isFalse);
      expect(effectiveMode(RecordMode.adhoc, 'installment_even'), RecordMode.settle);
      expect(effectiveMode(RecordMode.adhoc, 'installment_custom'), RecordMode.adhoc);
    });

    test('all-settled copy', () {
      expect(allSettledCopy('installment_even'), 'All installments on this plan are settled.');
      expect(allSettledCopy('installment_custom'),
          'All installments on this plan are settled. Switch to Ad-hoc to log an extra payment.');
    });
  });

  group('request bodies', () {
    test('settle: PATCH status paid with the incl-GST cash (CRM-PY-013 / 033)', () {
      final body = buildSettleBody(
        amountPaid: 3933,
        paidDate: DateTime(2026, 10, 24),
        method: 'upi',
        details: const SettlementDetails(gatewayRef: ' UTR123 '),
      );
      expect(body, {
        'status': 'paid',
        'amount_paid': '3933.00',
        'paid_date': '2026-10-24',
        'payment_method': 'upi',
        'gateway_ref': 'UTR123',
      });
    });

    test('settle with deductions sends tds / bank charge', () {
      final body = buildSettleBody(
        amountPaid: 8950,
        paidDate: DateTime(2026, 10, 24),
        method: 'bank_transfer',
        details: const SettlementDetails(tds: 1000, bankCharge: 50),
      );
      expect(body['amount_paid'], '8950.00');
      expect(body['tds_deducted'], '1000.00');
      expect(body['bank_charge'], '50.00');
      expect(body.containsKey('gateway_ref'), isFalse);
      expect(body.containsKey('bank_account_id'), isFalse);
    });

    test('ad-hoc: POST a paid record labelled', () {
      final body = buildAdhocBody(
        planId: 'plan-1',
        amount: 2500,
        paidDate: DateTime(2026, 10, 24),
        method: 'cash',
        label: 'Part payment',
      );
      expect(body, {
        'payment': 'plan-1',
        'amount_expected': '2500.00',
        'amount_paid': '2500.00',
        'status': 'paid',
        'paid_date': '2026-10-24',
        'payment_method': 'cash',
        'notes': 'Part payment',
      });
    });
  });

  group('lead conversion (CRM-PY-023)', () {
    const statuses = [
      {'lead_status_id': 'new', 'name': 'New', 'is_won': false, 'is_type_pick': true},
      {'lead_status_id': 'won2', 'name': 'Closed', 'is_won': true, 'is_type_pick': false},
      {'lead_status_id': 'won', 'name': 'Won', 'is_won': true, 'is_type_pick': true},
    ];

    test('needs a customer only on a lead-only quote', () {
      expect(planNeedsCustomer(hasCustomer: false, quotationUuid: 'q'), isTrue);
      expect(planNeedsCustomer(hasCustomer: true, quotationUuid: 'q'), isFalse);
      expect(planNeedsCustomer(hasCustomer: false, quotationUuid: ''), isFalse);
    });

    test('server refusal is recognised', () {
      expect(isCustomerRequiredFailure(code: 'CUSTOMER_REQUIRED'), isTrue);
      expect(isCustomerRequiredFailure(message: 'Convert the lead to a customer first.'), isTrue);
      expect(isCustomerRequiredFailure(message: 'Nope'), isFalse);
    });

    test('won pick prefers the type pick', () {
      expect(pickWonStatus(statuses), (id: 'won', name: 'Won'));
      expect(pickWonStatus(const [{'lead_status_id': 'a', 'name': 'A', 'is_won': false}]), isNull);
    });

    test('a New lead asks to mark Won', () {
      final s = quoteLeadStateFrom('L', const {'status': 'New', 'is_converted': false, 'pending_conversion': null}, statuses);
      expect(s.isWon, isFalse);
      expect(convertStepFor(s), ConvertStep.confirmMarkWon);
      expect(markWonPromptCopy(s.wonStatusName!),
          'This lead isn’t Won yet. Recording a payment will mark it Won and convert it to a customer.');
    });

    test('a Won lead converts; converted records; pending waits', () {
      final won = quoteLeadStateFrom('L', const {'status': 'Closed'}, statuses);
      expect(convertStepFor(won), ConvertStep.convert);
      expect(convertStepFor(quoteLeadStateFrom('L', const {'status': 'Won', 'is_converted': true}, statuses)),
          ConvertStep.recordNow);
      expect(convertStepFor(quoteLeadStateFrom('L', const {'status': 'New', 'pending_conversion': {'approval_id': 'x'}}, statuses)),
          ConvertStep.alreadyPending);
      expect(convertStepFor(quoteLeadStateFrom('L', const {'status': 'New'}, const [])), ConvertStep.noWonStatus);
    });

    test('toast copy', () {
      expect(leadConvertedToast('Acme'), 'Lead converted — customer Acme created');
      expect(leadConvertedToast(null), 'Lead converted to a customer');
    });
  });

  group('plan parsing', () {
    // Trimmed from live QTN-00041 (even split ×3, lead-only).
    final plan = RecordPaymentPlan.fromJson({
      'payment_id': 'p1',
      'quotation': 'q1',
      'quotation_number': 'QTN-00041',
      'customer': null,
      'payment_type': 'installment_even',
      'total_amount': '10000.00',
      'total_incl_gst': '11800.00',
      'amount_due_incl_gst': '11800.00',
      'records': [
        {
          'record_id': 'r2',
          'installment_number': 2,
          'notes': '',
          'amount_expected': '3333.05',
          'amount_paid': '0.00',
          'amount_due_gross': '3933.00',
          'balance_due': '3933.00',
          'settlement_state': 'pending',
          'status': 'pending',
          'lead_name': 'UAT Pay Even',
        },
        {
          'record_id': 'r1',
          'installment_number': 1,
          'notes': 'Installment 1 of 3',
          'amount_expected': '3333.05',
          'amount_paid': '3333.05',
          'amount_due_gross': '3933.00',
          'balance_due': '599.95',
          'settlement_state': 'partly_paid',
          'status': 'pending',
          'lead_name': 'UAT Pay Even',
        },
        {'record_id': 'r3', 'installment_number': 3, 'status': 'paid', 'amount_expected': '3333.90'},
      ],
    });

    test('summary and lead-only detection', () {
      expect(plan.needsCustomer, isTrue);
      expect(plan.who, 'UAT Pay Even');
      expect(plan.summary, 'QTN-00041 · UAT Pay Even · due ₹11,800 of ₹11,800 (incl. GST)');
      expect([for (final r in plan.openRecords) r.id], ['r1', 'r2']);
    });

    test('instalment option and open balance use the gross figures', () {
      final r1 = plan.records.first;
      expect(r1.optionLabel, 'Installment 1 of 3 · ₹3,933 · Partly paid');
      expect(r1.open, 599.95);
      final r2 = plan.records[1];
      expect(r2.optionLabel, 'Installment 2 · ₹3,933 · Pending');
      expect(r2.open, 3933);
    });

    test('plan option', () {
      final o = PlanOption.fromJson({
        'payment_id': 'p1',
        'quotation_number': 'QTN-00002',
        'customer_name': 'Arjun Roy',
        'total_incl_gst': '74339.00',
        'amount_due_incl_gst': '53339.33',
      });
      expect(o.label, 'QTN-00002 · Arjun Roy');
      expect(o.dueLine, 'Due ₹53,339.33 of ₹74,339 (incl. GST)');
    });
  });
}
