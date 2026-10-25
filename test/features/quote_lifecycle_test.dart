import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/crm/application/quote_lifecycle.dart';

Map<String, dynamic> _status(String id, String name, String type, {bool converted = false, bool active = true, bool def = false}) => {
      'quotation_status_id': id,
      'name': name,
      'status_type': type,
      'is_converted': converted,
      'is_active': active,
      'is_default': def,
    };

final _statuses = quoteStatusRows({
  'results': [
    _status('d', 'Draft', 'DRAFT', def: true),
    _status('s', 'Sent', 'SENT'),
    _status('a', 'Accepted', 'ACCEPTED', converted: true),
    _status('r', 'Rejected', 'REJECTED'),
    _status('e', 'Expired', 'EXPIRED'),
    _status('x', 'Superseded', 'SUPERSEDED'),
    _status('old', 'Old custom', 'SENT', active: false),
  ],
});

Map<String, dynamic> _row({
  String type = 'DRAFT',
  bool converted = false,
  String validUntil = '2026-11-21',
  String? sentAt,
  int lines = 1,
  String approval = 'NOT_REQUIRED',
  Object? block,
  String? plan,
  bool locked = false,
}) =>
    {
      'quotation_id': 'q1',
      'quotation_number': 'QTN-00028',
      'status': {'quotation_status_id': type.toLowerCase(), 'name': type, 'status_type': type, 'is_converted': converted},
      'valid_until': validUntil,
      'sent_at': sentAt,
      'line_items': List.generate(lines, (i) => {'line_no': i}),
      'approval_status': approval,
      'acceptance_block': block,
      'payment_plan_id': plan,
      'is_locked': locked,
      'payment_type': 'lumpsum',
      'billing_period_days': 30,
      'due_date': '2026-10-30',
    };

final _today = DateTime(2026, 10, 24);

AppError _conflict(String code, {String? next, Map<String, dynamic>? cause}) => AppError(
      type: AppErrorType.conflict,
      statusCode: 409,
      message: 'Server says no.',
      code: code,
      extra: {if (next != null) 'next': next, if (cause != null) 'cause': cause},
    );

void main() {
  group('statuses', () {
    test('picker hides Superseded, inactive and Draft after sent', () {
      final names = pickableStatuses(_statuses, 's', wasSent: true).map((s) => s.name).toList();
      expect(names, ['Sent', 'Accepted', 'Rejected', 'Expired']);
      expect(pickableStatuses(_statuses, 'd').map((s) => s.name), contains('Draft'));
      expect(pickableStatuses(_statuses, 'x').map((s) => s.name), contains('Superseded'));
    });

    test('findStatusOfType prefers converted / default and skips inactive', () {
      expect(findStatusOfType(_statuses, 'ACCEPTED')!.id, 'a');
      expect(findStatusOfType(_statuses, 'SENT')!.id, 's');
      expect(findStatusOfType(const [], 'SENT'), isNull);
    });

    test('legacy list falls back to names', () {
      final legacy = quoteStatusRows([
        {'quotation_status_id': '1', 'name': 'Lost'},
      ]);
      expect(isLegacyStatusList(legacy), isTrue);
      expect(resolveStatusType(legacy.first, true), 'REJECTED');
      expect(needsDeclineReason('REJECTED', 'SENT'), isTrue);
      expect(needsDeclineReason('REJECTED', 'REJECTED'), isFalse);
    });
  });

  group('gates', () {
    test('mark as sent content blocks', () {
      expect(quoteLifecycleActions(QuoteFacts.fromRow(_row(lines: 0)), today: _today).sendBlockedReason, kSendNeedsLine);
      expect(quoteLifecycleActions(QuoteFacts.fromRow(_row(validUntil: '')), today: _today).sendBlockedReason, kSendNeedsValidity);
      expect(quoteLifecycleActions(QuoteFacts.fromRow(_row(validUntil: '2026-10-01')), today: _today).sendBlockedReason,
          kSendValidityPassed);
      final ok = quoteLifecycleActions(QuoteFacts.fromRow(_row()), today: _today);
      expect(ok.canMarkSent, isTrue);
      expect(ok.sendBlocked, isFalse);
    });

    test('approval pending greys send and accept', () {
      final a = quoteLifecycleActions(QuoteFacts.fromRow(_row(type: 'SENT', sentAt: '2026-10-20', approval: 'PENDING')), today: _today);
      expect(a.acceptBlockedReason, 'The discount needs approval before this quote can be accepted.');
      final d = quoteLifecycleActions(QuoteFacts.fromRow(_row(approval: 'PENDING')), today: _today);
      expect(d.sendBlockedReason, 'Waiting for discount approval — it can be marked as sent once approved');
    });

    test('accept blocked reasons', () {
      expect(quoteLifecycleActions(QuoteFacts.fromRow(_row()), today: _today).acceptBlockedReason, kAcceptNotSent);
      final server = quoteLifecycleActions(
          QuoteFacts.fromRow(_row(block: {'code': 'QUOTE_NOT_SENT', 'detail': 'Mark this quote as Sent before accepting it.'})),
          today: _today);
      expect(server.acceptBlockedReason, 'Mark this quote as Sent before accepting it.');
      final expired = quoteLifecycleActions(
          QuoteFacts.fromRow(_row(type: 'SENT', sentAt: '2026-10-01', validUntil: '2026-10-10')),
          today: _today);
      expect(expired.acceptBlockedReason, kAcceptExpired);
      expect(expired.canRenew, isTrue);
      expect(expired.canRevise, isFalse);
      final ok = quoteLifecycleActions(QuoteFacts.fromRow(_row(type: 'SENT', sentAt: '2026-10-20')), today: _today);
      expect(ok.acceptBlocked, isFalse);
      expect(ok.canRevise, isTrue);
      expect(ok.canReject, isTrue);
    });

    test('accepted / superseded', () {
      final acc = quoteLifecycleActions(QuoteFacts.fromRow(_row(type: 'ACCEPTED', converted: true, plan: 'p1')), today: _today);
      expect(acc.canAccept, isFalse);
      expect(acc.canRevise, isFalse);
      expect(acc.canMarkSent, isFalse);
      final sup = quoteLifecycleActions(QuoteFacts.fromRow(_row(type: 'SUPERSEDED')), today: _today);
      expect(sup.isReadOnly, isTrue);
      expect(sup.canAccept, isFalse);
    });
  });

  group('delete eligibility', () {
    test('accepted or with a plan is blocked', () {
      expect(deleteBlockedReason(QuoteFacts.fromRow(_row())), '');
      expect(deleteBlockedReason(QuoteFacts.fromRow(_row(type: 'ACCEPTED', converted: true))), kDeleteBlocked);
      expect(deleteBlockedReason(QuoteFacts.fromRow(_row(type: 'SENT', plan: 'p1'))), kDeleteBlocked);
      expect(kDeleteBlocked, 'Accepted or paid quotes can’t be deleted — cancel or credit-note in accounting first');
    });
  });

  group('accept dialog', () {
    final facts = QuoteFacts.fromRow(_row(type: 'SENT', sentAt: '2026-10-20T10:00:00+05:30'));
    final w = acceptDateWindow(facts, today: _today);

    test('window and date validation', () {
      expect(w.max, '2026-10-24');
      expect(w.min, '2026-10-20');
      expect(validateAcceptedOn('2026-10-25', w), 'The acceptance date can’t be in the future.');
      expect(validateAcceptedOn('2026-10-19', w), 'The acceptance date can’t be before the quote was sent (2026-10-20).');
      expect(validateAcceptedOn('2026-10-22', w), isNull);
      expect(validateAcceptedOn('', w), 'Pick the date the customer accepted.');
    });

    test('back-dated window', () {
      final f = QuoteFacts.fromRow(_row(type: 'EXPIRED', sentAt: '2026-10-01', block: {
        'code': 'QUOTE_EXPIRED',
        'detail': 'Expired',
        'cause': {'accepted_on_max': '2026-10-10'},
      }));
      final bw = acceptDateWindow(f, today: _today);
      expect(bw.backdatedOnly, isTrue);
      expect(bw.max, '2026-10-10');
      expect(acceptDateHint(bw),
          'This quote was valid until 2026-10-10. Enter the date the customer accepted — on or before that day.');
      expect(quoteLifecycleActions(f, today: _today).canAccept, isTrue);
      expect(quoteLifecycleActions(f, today: _today).acceptBlocked, isFalse);
    });

    test('schedule validation', () {
      String? err(String c, String p, String f) =>
          resolveSchedule(count: c, periodDays: p, firstDue: f, quote: facts, acceptedOn: '2026-10-24').$2;
      expect(err('0', '30', ''), 'Choose between 1 and 60 instalments.');
      expect(err('61', '30', ''), 'Choose between 1 and 60 instalments.');
      expect(err('3', '0', ''), 'The interval must be between 1 and 366 days.');
      expect(err('3', '367', ''), 'The interval must be between 1 and 366 days.');
      expect(err('2', '30', '2026-10-01'), 'The first instalment can’t be due before the acceptance date (24-Oct-2026).');
      expect(err('1', '30', ''), isNull);
    });

    test('schedule summary and change detection', () {
      final (s, _) = resolveSchedule(count: '3', periodDays: '30', firstDue: '', quote: facts, acceptedOn: '2026-10-24');
      expect(scheduleSummary(s!), '3 instalments from 30-Oct-2026, every 30 days');
      expect(scheduleChanged(s, facts, '2026-10-24'), isTrue);
      final base = defaultSchedule(facts, '2026-10-24');
      expect(scheduleChanged(base, facts, '2026-10-24'), isFalse);
      expect(acceptPlanSummary(facts, '2026-10-24').schedule, 'Lump sum, due 30-Oct-2026');
      expect(acceptPlanSummary(facts, '2026-10-24').typeLabel, 'Lump sum');
    });
  });

  group('decline / renew', () {
    test('decline validation', () {
      expect(validateDeclineDraft('', '', ['r1']).error, 'Choose why the quote was declined.');
      expect(validateDeclineDraft('r1', 'x' * 2001, ['r1']).error, 'Keep the note under 2000 characters.');
      expect(validateDeclineDraft('gone', '', ['r1']).error, 'That reason is no longer available — choose another.');
      final ok = validateDeclineDraft('r1', '  cheaper vendor ', ['r1']);
      expect(ok.error, isNull);
      expect(ok.note, 'cheaper vendor');
    });

    test('renew date', () {
      expect(validateRenewDate('', today: _today), isNull);
      expect(validateRenewDate('2026-10-24', today: _today),
          'Pick a date in the future, or leave it blank for the default validity.');
      expect(validateRenewDate('2026-10-25', today: _today), isNull);
    });
  });

  group('conflicts and locks', () {
    test('lifecycle conflict parsing', () {
      final c = lifecycleConflict(_conflict('ANOTHER_QUOTE_ACCEPTED',
          next: 'OPEN_ACCEPTED_QUOTE', cause: {'accepted_quotation_id': 'q9', 'accepted_quotation_number': 'QTN-00030'}));
      expect(c!.code, 'ANOTHER_QUOTE_ACCEPTED');
      expect(c.next, 'OPEN_ACCEPTED_QUOTE');
      expect(c.acceptedQuotationNumber, 'QTN-00030');
      expect(c.message, 'Server says no.');
      expect(lifecycleConflict(_conflict('QUOTE_LOCKED', next: 'BOGUS'))!.next, isNull);
      expect(lifecycleConflict(_conflict('ACCOUNTING_POSTING_REJECTED')), isNull);
      expect(lifecycleConflict(const AppError(type: AppErrorType.validation, message: 'x')), isNull);
      final r = lifecycleConflict(_conflict('QUOTE_NOT_REVISABLE',
          next: 'OPEN_LATEST_REVISION', cause: {'latest_revision_id': 'q3', 'latest_quotation_number': 'QTN-00012-R3'}));
      expect(r!.latestQuotationNumber, 'QTN-00012-R3');
    });

    test('lock kinds', () {
      final revert = AppError(
          type: AppErrorType.validation,
          message: 'status_id: This quotation has a recorded payment',
          fieldErrors: const {'status_id': ['This quotation has a recorded payment']},
          cause: DioException(requestOptions: RequestOptions()));
      expect(quoteLockKind(revert, wasStatusChange: true, wasAccepted: true), QuoteLockKind.revert);
      const paid = AppError(type: AppErrorType.validation, message: 'The amounts are locked.');
      expect(quoteLockKind(paid, wasStatusChange: false, wasAccepted: false), QuoteLockKind.paid);
      expect(quoteLockCopy[QuoteLockKind.paid]!.title, 'This quote is locked.');
      expect(quoteLockCopy[QuoteLockKind.revert]!.title, 'This quote can’t leave Accepted.');
    });
  });

  group('misc', () {
    test('revisions', () {
      expect(baseQuoteNumber('QTN-00012-R2'), 'QTN-00012');
      final latest = pickLatestRevision([
        {'quotation_id': 'a', 'quotation_number': 'QTN-00012-R2', 'revision_no': 2},
        {'quotation_id': 'b', 'quotation_number': 'QTN-00012-R3', 'revision_no': 3},
        {'quotation_id': 'c', 'quotation_number': 'QTN-00013', 'revision_no': 9},
      ], const QuoteFacts(id: 'z', number: 'QTN-00012', revisionNo: 0));
      expect(latest!['quotation_id'], 'b');
    });

    test('labels and dates', () {
      expect(planTypeLabel('installment_even'), 'Instalments – even split');
      expect(planTypeLabel('lumpsum'), 'Lump sum');
      expect(amountsAreLabel('EXCLUSIVE'), 'Tax exclusive');
      expect(fmtQuoteDate('2026-10-05'), '05-Oct-2026');
    });

    test('payment instructions', () {
      expect(QuotePaymentInstructions.fromResponse({'payment_instructions': null}), isNull);
      final pi = QuotePaymentInstructions.fromResponse({
        'payment_instructions': {
          'bank_accounts': [
            {'bank_name': 'HDFC', 'account_number': '501', 'ifsc': 'HDFC0001'}
          ],
          'upi_id': 'acme@hdfc',
          'upi_qr_data_uri': 'data:image/png;base64,iVBORw0KGgo=',
          'payment_link': 'javascript:alert(1)',
          'amount': '1180.00',
        }
      })!;
      expect(pi.bankAccounts.single.ifsc, 'HDFC0001');
      expect(pi.upiQrBase64, 'iVBORw0KGgo=');
      expect(pi.paymentLink, '');
      expect(pi.amount, '1180.00');
    });

    test('document fields', () {
      const f = DocTemplateField(key: 'start', label: 'Start', type: 'date', required: true);
      expect(documentFieldProblem(f, ''), 'Start is required.');
      expect(documentFieldProblem(f, 'tomorrow'), 'Start must be a date.');
      expect(documentFieldProblem(f, '2026-10-24'), '');
    });
  });
}
