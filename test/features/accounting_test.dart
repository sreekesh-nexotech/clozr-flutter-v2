// The accounting module's contract with the API (docs-flutter/
// ACCOUNTING_FRONTEND_HANDOVER.md): the JSON mappers, the structured-error
// model, the skipped-post outcome and the request bodies the posting paths
// send. Fixtures follow the handover's documented shapes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/accounting/application/providers/accounting_providers.dart';
import 'package:clozrapp/features/auth/application/providers/auth_providers.dart';
import 'package:clozrapp/features/auth/domain/entities/module_access.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/core/utils/money_format.dart';
import 'package:clozrapp/features/accounting/infrastructure/data_sources/remote/acc_remote_support.dart';
import 'package:clozrapp/features/accounting/infrastructure/data_sources/remote/accounting_documents_remote_ds.dart';
import 'package:clozrapp/features/accounting/infrastructure/data_sources/remote/accounting_mappers.dart';
import 'package:clozrapp/features/accounting/infrastructure/data_sources/remote/accounting_settlement_remote_ds.dart';
import 'package:clozrapp/features/accounting/presentation/sheets/party_tax_profile_sheet.dart';
import 'package:clozrapp/features/crm/application/quote_draft.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/payments_remote_ds.dart';
import 'package:clozrapp/features/helpdesk/infrastructure/data_sources/remote/tickets_remote_ds.dart';

/// Records every request and answers with [body] / [status].
class _Adapter implements HttpClientAdapter {
  _Adapter({this.body = const {}, this.status = 200});

  final Object body;
  final int status;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiService _api(_Adapter a) =>
    ApiService(tokens: TokenStorage(), dio: Dio(BaseOptions(baseUrl: 'https://x/api/v1'))..httpClientAdapter = a);

void main() {
  group('document mapper', () {
    final row = {
      'document_id': 'd1',
      'doc_type': 'TAX_INVOICE',
      'direction': 'OUTWARD',
      'number': 'INV/26-27/0042',
      'document_date': '2026-09-20',
      'customer': 'c1',
      'grand_total': '118000.50',
      'taxable_total': 100000,
      'tax_cgst': '9000.25',
      'tax_sgst': '9000.25',
      'status': 'ISSUED',
      'payment_state': 'PARTIAL',
      'open_balance': '18000.50',
      'warnings': [
        {'code': 'LATE_INVOICE', 'supply_date': '2026-08-01', 'document_date': '2026-09-20'},
        'LEGACY_STRING',
      ],
      'config_draft_rows': [{}, {}],
      'party_snapshot': {'gstin': '32AAAAA0000A1Z5'},
      'lines': [
        {'line_no': 2, 'description': 'Second', 'qty': '1.000', 'unit_price': '10.00'},
        {'line_no': 1, 'description': 'First', 'qty': '2.500', 'unit_price': '40000.00', 'hsn_sac': '998313', 'rate_pct': '18.00'},
      ],
      'tax_lines': [
        {'head': 'CGST', 'direction': 'OUTPUT', 'amount': '9000.25', 'rate_pct': '9.00'},
      ],
    };

    test('keeps money as the server sent it — paise included', () {
      final d = mapDocument(row)!;
      expect(d.grandTotal, '118000.50');
      expect(d.openBalance, '18000.50');
      // A number becomes the two-decimal string the rest of the app expects.
      expect(d.taxableTotal, '100000.00');
    });

    test('orders lines by line_no and reads their tax snapshot', () {
      final d = mapDocument(row)!;
      expect(d.lines.map((l) => l.description), ['First', 'Second']);
      expect(d.lines.first.hsnSac, '998313');
      expect(d.lines.first.qty, '2.500');
    });

    test('reads warnings as objects and as bare strings', () {
      final d = mapDocument(row)!;
      expect(d.warnings.map((w) => w.code), ['LATE_INVOICE', 'LEGACY_STRING']);
      expect(d.warnings.first.data['supply_date'], '2026-08-01');
      expect(d.configDraftRows, 2);
    });

    test('status helpers and display number', () {
      final d = mapDocument(row)!;
      expect(d.isIssued, isTrue);
      expect(d.canCreditNote, isTrue);
      expect(d.displayNumber, 'INV/26-27/0042');
      final draft = mapDocument({'document_id': 'd2', 'status': 'DRAFT'})!;
      expect(draft.displayNumber, 'Draft');
      expect(draft.canCreditNote, isFalse);
    });

    test('a row with no id is skipped, not fatal', () {
      expect(mapDocument({'number': 'X'}), isNull);
      expect(mapDocuments([row, {'number': 'X'}, 'junk']).length, 1);
    });
  });

  group('masters and settlement mappers', () {
    test('party tax profile unwraps the effective-dated attributes', () {
      final p = mapPartyTaxProfile({
        'pan': 'AAAAA0000A',
        'tds_applicable': true,
        'attributes': [
          {'attribute': 'REGISTRATION_TYPE', 'value': {'type': 'REGISTERED'}, 'effective_to': null},
          {'attribute': 'GSTIN', 'value': {'gstin': 'OLD'}, 'effective_to': '2026-01-01'},
          {'attribute': 'GSTIN', 'value': {'gstin': '27AAPFU0939F1ZV'}, 'effective_to': null},
          {'attribute': 'STATE', 'value': '27'},
        ],
      });
      expect(p.registrationType, 'REGISTERED');
      expect(p.gstin, '27AAPFU0939F1ZV', reason: 'the open row wins over a closed one');
      expect(p.stateCode, '27', reason: 'older rows hold a bare scalar');
      expect(p.isB2b, isTrue);
      expect(p.tdsApplicable, isTrue);
    });

    test('receipt with allocations', () {
      final r = mapReceipt({
        'receipt_id': 'r1',
        'customer_id': 'c1',
        'amount': '5000.00',
        'unallocated': '250.00',
        'status': 'POSTED',
        'allocations': [
          {'document_id': 'd1', 'amount_applied': '4750.00'},
          {'amount_applied': '1.00'},
        ],
      })!;
      expect(r.unallocated, '250.00');
      expect(r.allocations.single.documentId, 'd1');
      expect(r.isPosted, isTrue);
    });

    test('aging reads the vendor keys for AP and keeps names', () {
      final a = mapAging({
        'as_of': '2026-09-24',
        'rows': [
          {'vendor_id': 'v1', 'vendor_name': 'Acme', '0-30': '10.00', '90+': 5, 'total': '15.00'},
        ],
        'totals': {'total': '15.00', '90+': '5.00'},
      }, vendor: true);
      expect(a.rows.single.partyName, 'Acme');
      expect(a.rows.single.buckets['90+'], '5.00');
      expect(a.grandTotal, '15.00');
    });

    test('period register and the GST period covering a day', () {
      final reg = mapPeriodRegister({
        'fy_label': '2026-27',
        'gst_periods': [
          {'gst_period_id': 'g1', 'start_date': '2026-09-01', 'end_date': '2026-09-30', 'gstr1_status': 'FILED'},
        ],
        'tds_periods': [
          {'tds_period_id': 't2', 'quarter': 2, 'status': 'OPEN'},
        ],
      });
      expect(reg.gstPeriods.single.gstr1Status, 'FILED');
      expect(reg.gstPeriodFor(DateTime(2026, 9, 24))?.id, 'g1');
      expect(reg.gstPeriodFor(DateTime(2026, 10, 1)), isNull);
      expect(reg.tdsPeriods.single.quarter, 2);
    });

    test('TDS summary keeps the count a count', () {
      final t = mapTdsSummary({
        'rows': [
          {'nature_key': 'PROFESSIONAL', 'pending': '1000.00', 'count': 3},
        ],
        'totals': {'pending': '1000.00', 'count': 3},
      });
      expect(t.totals['count'], '3');
      expect(t.totals['pending'], '1000.00');
    });
  });

  group('structured errors (handover §4)', () {
    AppError fromBody(int status, Object body) => AppError.fromDio(DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: status, data: body),
        ));

    test('a guard keeps code, cause and next', () {
      final e = fromBody(409, {
        'code': 'RATE_VARIANT_REQUIRED',
        'detail': 'Pick a rate.',
        'cause': {'line_no': 1, 'candidates': []},
        'next': 'PIN_VARIANT_ON_PRODUCT',
      });
      expect(e.type, AppErrorType.conflict);
      expect(e.code, 'RATE_VARIANT_REQUIRED');
      expect(e.causeMap['line_no'], 1);
      expect(e.nextAction, 'PIN_VARIANT_ON_PRODUCT');
      expect(e.message, 'Pick a rate.');
    });

    test('the activation gate is recognised', () {
      final e = fromBody(409, {'code': 'ACCOUNTING_NOT_ACTIVE', 'detail': 'Not active.', 'cause': {}});
      expect(e.isAccountingInactive, isTrue);
    });

    test('a flattened 403 has no string code — never parse it for the plan gate', () {
      final e = fromBody(403, {'code': 403, 'message': 'Your current plan does not include this feature.'});
      expect(e.code, isNull);
      expect(e.type, AppErrorType.forbidden);
      expect(e.causeMap, isEmpty);
    });
  });

  group('posting paths', () {
    test('a skipped post is its own outcome', () {
      final out = postOutcome({'skipped': true, 'detail': 'Event skipped'}, mapReceipt);
      expect(out.skipped, isTrue);
      expect(out.skipReason, 'Event skipped');
      expect(postOutcome({'receipt_id': 'r1'}, mapReceipt).value?.id, 'r1');
    });

    test('record receipt sends the event id and drops blanks', () async {
      final a = _Adapter(body: {'receipt_id': 'r1', 'amount': '100.00', 'unallocated': '0.00'}, status: 201);
      final ds = AccountingSettlementRemoteDataSource(_api(a));
      final out = await ds.recordReceipt({
        'customer': 'c1',
        'amount_received': '100.00',
        'source_account_kind': 'CASH',
        'receipt_date': '2026-09-24',
        'bank_account': null,
        'reference': '',
        'event_id': 'e-1',
      });
      final sent = a.requests.single.data as Map;
      expect(a.requests.single.path, '/accounting/settlement/receipts/');
      expect(sent['event_id'], 'e-1');
      expect(sent.containsKey('bank_account'), isFalse);
      expect(sent.containsKey('reference'), isFalse);
      expect(out.value?.id, 'r1');
    });

    test('create invoice posts to the manual route', () async {
      final a = _Adapter(body: {'document_id': 'd9', 'status': 'DRAFT'}, status: 201);
      final ds = AccountingDocumentsRemoteDataSource(_api(a));
      final doc = await ds.createInvoice({
        'doc_type': 'TAX_INVOICE',
        'document_date': '2026-09-24',
        'customer': null,
        'lines': [
          {'line_no': 1, 'description': 'Work', 'qty': '1', 'unit_price': '100.00'},
        ],
      });
      expect(a.requests.single.path, '/accounting/documents/invoices/');
      expect((a.requests.single.data as Map).containsKey('customer'), isFalse);
      expect(doc?.isDraft, isTrue);
    });

    test('event ids are v4 UUIDs and differ per call', () {
      final a = newEventId();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue);
      expect(newEventId(), isNot(a));
    });
  });

  group('mark paid (handover §9.1)', () {
    test('sends cash, the chosen date and the deductions as strings', () async {
      final a = _Adapter(body: {'record_id': 'r1', 'posted_receipt_id': 'rc1'});
      final ds = PaymentsRemoteDataSource(_api(a));
      final posted = await ds.markRecordPaid(
        'r1',
        amountPaid: '9000.50',
        method: 'upi',
        paidDate: DateTime(2026, 9, 2),
        tdsDeducted: '1000.00',
        bankCharge: '0',
        bankAccountId: 'b1',
        treatAs: 'ADVANCE',
      );
      final sent = a.requests.single.data as Map;
      expect(sent['status'], 'paid');
      expect(sent['amount_paid'], '9000.50');
      expect(sent['paid_date'], '2026-09-02', reason: "the customer's date, not today");
      expect(sent['tds_deducted'], '1000.00');
      expect(sent.containsKey('bank_charge'), isFalse, reason: 'zero is not sent');
      expect(sent['bank_account_id'], 'b1');
      expect(sent['treat_as'], 'ADVANCE');
      expect(posted, isTrue);
    });

    test('a record carries the exact amount and what the ledger made of it', () {
      final p = paymentRecordFromApi({
        'record_id': 'r1',
        'status': 'pending',
        'amount_expected': '12500.50',
        'due_date': '2026-10-01',
        'linked_document_id': 'd1',
        'record_summary': {
          'document': {'document_id': 'd1', 'number': 'INV/26-27/0001', 'status': 'ISSUED', 'payment_state': 'UNPAID'},
        },
      })!;
      expect(p.amountExact, '12500.50');
      expect(p.amountNum, 12501, reason: 'the display twin still rounds');
      expect(p.linkedDocumentId, 'd1');
      expect(p.recordSummary?.documentNumber, 'INV/26-27/0001');
      expect(p.recordSummary?.hasReceipt, isFalse);
    });
  });

  group('CRM writes that accounting depends on', () {
    test('a quote carries its tax basis, place of supply and contract ref', () {
      const draft = QuoteDraft(
        leadId: 'l1',
        amountsAre: 'EXCLUSIVE',
        placeOfSupplyStateCode: '32',
        contractRef: ' PO-7 ',
        lines: [QuoteDraftLine(description: 'X', quantity: '1.000', unitPrice: '10.00', productId: 'p1')],
      );
      final body = draft.toCreateJson();
      expect(body['amounts_are'], 'EXCLUSIVE');
      expect(body['place_of_supply_state_code'], '32');
      expect(body['contract_ref'], 'PO-7');
      expect((body['line_items'] as List).single['product_id'], 'p1');
      final bare = const QuoteDraft(leadId: 'l1').toCreateJson();
      expect(bare.containsKey('amounts_are'), isFalse);
    });

    test('ticket billing fields survive the write filter', () {
      final out = TicketsRemoteDataSource.writePayload({
        'billable': true,
        'billable_amount': '1500.00',
        'billable_product_id': '6f1f0c1e-2b1a-4c1e-9a1e-1a2b3c4d5e6f',
      });
      expect(out['billable'], isTrue);
      expect(out['billable_amount'], '1500.00');
      expect(out['billable_product_id'], '6f1f0c1e-2b1a-4c1e-9a1e-1a2b3c4d5e6f');
      final cleared = TicketsRemoteDataSource.writePayload({
        'billable': false,
        'billable_amount': null,
        'billable_product_id': 'not-a-uuid',
      });
      expect(cleared['billable_amount'], isNull);
      expect(cleared['billable_product_id'], isNull);
    });
  });

  group('small helpers', () {
    test('GSTIN checksum', () {
      expect(gstinValid('27AAPFU0939F1ZV'), isTrue);
      expect(gstinValid('27aapfu0939f1zv'), isTrue, reason: 'case-insensitive');
      expect(gstinValid('27AAPFU0939F1ZW'), isFalse, reason: 'wrong check character');
      expect(gstinValid('27AAPFU0939F1Z'), isFalse);
    });

    test('money formatting keeps paise and Indian grouping', () {
      expect(formatMoneyStr('125000.5'), '₹1,25,000.50');
      expect(formatMoneyStr(null), '—');
      expect(moneyInput('1,250.5'), '1250.50');
      expect(moneyInput('abc'), isNull);
      expect(isoDay(DateTime(2026, 4, 1)), '2026-04-01');
    });
  });

  group('money posting (live /auth/me/modules/ shape)', () {
    Future<AccPerm> permFor(Map<String, dynamic> json, String module) async {
      final c = ProviderContainer(overrides: [
        moduleAccessProvider.overrideWith((ref) async => ModuleAccess.fromJson(json)),
      ]);
      addTearDown(c.dispose);
      await c.read(moduleAccessProvider.future);
      return c.read(accPermProvider(module));
    }

    const all = {'can_read': true, 'can_create': true, 'can_update': true, 'can_approve': true};

    test('full-access staff get no posting buttons without the codename', () async {
      final p = await permFor({
        'is_staff': true,
        'full_access': true,
        'modules': {'acc_settlement': all},
        'money_posting': {
          'bypass': false,
          'modules': {
            'acc_settlement': {'can_create': false, 'can_update': false},
          },
        },
      }, 'acc_settlement');
      expect(p.read, isTrue);
      expect(p.create, isFalse);
      expect(p.update, isFalse);
    });

    test('an Accounting role keeps what money_posting grants', () async {
      final p = await permFor({
        'modules': {'acc_purchase': all},
        'money_posting': {
          'bypass': false,
          'modules': {
            'acc_purchase': {'can_create': true, 'can_approve': true},
          },
        },
      }, 'acc_purchase');
      expect(p.create, isTrue);
      expect(p.approve, isTrue);
    });

    test('modules outside money_posting are untouched', () async {
      final p = await permFor({
        'full_access': true,
        'modules': {'acc_document': all},
        'money_posting': {'bypass': false, 'modules': {}},
      }, 'acc_document');
      expect(p.create, isTrue);
      expect(p.approve, isTrue);
    });
  });
}
