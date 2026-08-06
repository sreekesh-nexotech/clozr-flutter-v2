// The New quote form used to end in `toast.show('Quote created')` with no
// request. These cover what replaced it: the POST body it now builds, and the
// schema/template calls that drive the form. Fixtures are the real dev-backend
// shapes (Acme's un-backfilled quote schema included, deliberately).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/application/quote_draft.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/quotes_remote_ds.dart';

Map<String, dynamic> _col(String name, String label, int order,
        {bool visible = true}) =>
    {
      'name': name,
      'label': label,
      'order': order,
      'visible': visible,
      'is_protected': false,
      'field_info': {'type': 'string'},
    };

/// Acme's live detail schema — note it has no `template_name`/`owner`/
/// `line_items` because the org has not been backfilled yet.
final _quoteSchemaBody = {
  'model': 'Quotation',
  'view_type': 'detail',
  'has_org_config': true,
  'all_fields': {
    'columns': [
      _col('quotation_number', 'Quote No.', 1),
      _col('quotation_title', 'Title', 2),
      _col('status', 'Status', 3),
      _col('total_amount', 'Amount', 4),
      _col('currency', 'Currency', 5),
      _col('valid_until', 'Valid Until', 6),
      _col('payment_type', 'Payment Type', 8),
      _col('notes', 'Notes', 10),
      _col('terms_and_conditions', 'terms_and_conditions', 14),
      _col('billing_period_days', 'billing_period_days', 16),
      _col('created_at', 'Issued', 20, visible: false),
    ],
  },
};

/// Captures the request and answers with a created quote.
class _CaptureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  Object? body;

  _CaptureAdapter({this.body});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body ?? _quoteSchemaBody),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

QuotesRemoteDataSource _dsWith(_CaptureAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
    ..httpClientAdapter = adapter;
  return QuotesRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));
}

const _line = QuoteDraftLine(
  description: 'Turnkey Office Fit-out',
  quantity: 2,
  unitPrice: '2400',
);

void main() {
  final schema = ViewSchema.fromResponse(_quoteSchemaBody);

  group('the create payload matches the documented contract', () {
    test('a minimal draft sends the lead, currency and line items', () {
      const draft = QuoteDraft(leadId: 'lead-1', lines: [_line]);

      final json = draft.toCreateJson(schema: schema);

      expect(json['lead'], 'lead-1');
      expect(json['currency'], 'INR');
      expect(json['line_items'], [
        {'description': 'Turnkey Office Fit-out', 'quantity': 2, 'unit_price': '2400'}
      ]);
      // The server stamps the owner and only gains a customer on conversion —
      // sending either would be ignored at best.
      expect(json.containsKey('owner'), isFalse);
      expect(json.containsKey('owner_id'), isFalse);
      expect(json.containsKey('customer'), isFalse);
    });

    test('payment_type is the API enum, not the display label', () {
      const draft = QuoteDraft(
        leadId: 'lead-1',
        paymentType: QuotePaymentType.installmentEven,
        numInstallments: 3,
        lines: [_line],
      );

      final json = draft.toCreateJson(schema: schema);

      // The old form would have sent "Installments – even split".
      expect(json['payment_type'], 'installment_even');
      expect(json['num_installments'], 3);
    });

    test('num_installments rides only with an even split', () {
      for (final type in [
        QuotePaymentType.lumpsum,
        QuotePaymentType.subscription,
        QuotePaymentType.installmentCustom,
      ]) {
        final json = QuoteDraft(leadId: 'l', paymentType: type, lines: const [_line])
            .toCreateJson(schema: schema);
        expect(json.containsKey('num_installments'), isFalse,
            reason: '${type.value} must not send a count');
      }
    });

    test('blank optionals are omitted rather than sent empty', () {
      const draft = QuoteDraft(leadId: 'l', title: '   ', notes: '', lines: [_line]);

      final json = draft.toCreateJson(schema: schema);

      // An empty string would overwrite the org default with a blank.
      expect(json.containsKey('quotation_title'), isFalse);
      expect(json.containsKey('notes'), isFalse);
    });

    test('valid_until is sent as YYYY-MM-DD', () {
      final json = QuoteDraft(
        leadId: 'l',
        validUntil: DateTime(2026, 9, 4),
        lines: const [_line],
      ).toCreateJson(schema: schema);

      expect(json['valid_until'], '2026-09-04');
    });

    test('a field the org configured away is not sent', () {
      final narrow = ViewSchema.fromResponse({
        'has_org_config': true,
        'all_fields': {
          'columns': [_col('notes', 'Notes', 1)],
        },
      });

      final json = QuoteDraft(
        leadId: 'l',
        title: 'Revamp',
        notes: 'Valid 30 days',
        lines: const [_line],
      ).toCreateJson(schema: narrow);

      expect(json['notes'], 'Valid 30 days');
      expect(json.containsKey('quotation_title'), isFalse,
          reason: 'title is hidden on this org’s layout');
      // The required parts survive regardless of layout.
      expect(json['lead'], 'l');
      expect(json['line_items'], isNotEmpty);
    });

    test('the empty schema sends everything the form collected', () {
      final json = QuoteDraft(
        leadId: 'l',
        title: 'Revamp',
        notes: 'n',
        terms: 't',
        lines: const [_line],
      ).toCreateJson();

      expect(json['quotation_title'], 'Revamp');
      expect(json['notes'], 'n');
      expect(json['terms_and_conditions'], 't');
    });
  });

  group('submittability', () {
    test('needs both a lead and at least one line', () {
      expect(const QuoteDraft(leadId: '', lines: [_line]).isSubmittable, isFalse);
      expect(const QuoteDraft(leadId: 'l').isSubmittable, isFalse);
      expect(const QuoteDraft(leadId: 'l', lines: [_line]).isSubmittable, isTrue);
    });
  });

  group('the endpoints the form calls', () {
    test('the schema call asks for detail, never form', () async {
      final adapter = _CaptureAdapter();
      final ds = _dsWith(adapter);

      final result = await ds.fetchQuoteSchema();

      expect(adapter.requests.single.path, '/quotations/quotations/schema/');
      // `form` omits template/lead/owner/line_items — the whole reason for this.
      expect(adapter.requests.single.queryParameters['view_type'], 'detail');
      expect(result.shows('payment_type'), isTrue);
      expect(result.shows('created_at'), isFalse);
    });

    test('templates read template_name and flag the default', () async {
      final adapter = _CaptureAdapter(body: {
        'count': 2,
        'results': [
          {'template_id': 't1', 'template_name': 'Modern', 'is_default': false},
          {'template_id': 't2', 'template_name': 'Standard', 'is_default': true},
        ],
      });

      final templates = await _dsWith(adapter).fetchTemplates();

      expect(adapter.requests.single.path, '/quotations/templates/');
      expect(templates.map((t) => t.name).toList(), ['Modern', 'Standard']);
      expect(templates.firstWhere((t) => t.isDefault).id, 't2');
    });

    test('createQuote POSTs to the quotations collection', () async {
      final adapter = _CaptureAdapter(body: {
        'quotation_id': 'q1',
        'quotation_number': 'QTN-00017',
        'status': {'name': 'Draft'},
        'total_amount': '4800.00',
      });

      final quote = await _dsWith(adapter)
          .createQuote(const QuoteDraft(leadId: 'l', lines: [_line]).toCreateJson());

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/quotations/quotations/');
      expect((req.data as Map)['lead'], 'l');
      expect(quote?.id, 'QTN-00017');
    });

    test('a broken schema response degrades to the empty layout', () async {
      final adapter = _CaptureAdapter(body: {'unexpected': true});

      expect((await _dsWith(adapter).fetchQuoteSchema()).isEmpty, isTrue);
    });
  });
}
