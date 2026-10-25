import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../application/quote_lifecycle.dart';

/// The quote detail's lifecycle endpoints (webapp `quotes.api.ts` /
/// `quoteSales.api.ts` / `salesContent.api.ts`). Writes throw [AppError];
/// the screen decides whether that is a banner, a dialog error or a toast.
class QuoteActionsRemoteDataSource {
  const QuoteActionsRemoteDataSource(this._api);

  final ApiService _api;

  static const statusesPath = '/quotations/statuses/';
  static const declineReasonsPath = '/quotations/decline-reasons/';
  static const docTemplatesPath = '/sales-content/documents/templates/';
  static const generateDocPath = '/sales-content/documents/generate/';

  static String _q(String id, String suffix) => '${ApiEndpoints.quotation(id)}$suffix';

  /// `GET /quotations/statuses/` — every row, inactive included, with
  /// `status_type`.
  Future<List<QuoteStatusRow>> statuses() async =>
      quoteStatusRows(await _api.get(statusesPath, query: {'page_size': 100}, quiet: true));

  /// `GET /quotations/decline-reasons/?is_active=true` → `(id, name)`.
  Future<List<({String id, String name})>> declineReasons() async {
    final body = await _api.get(declineReasonsPath, query: {'is_active': 'true', 'page_size': 100});
    final list = body is Map ? body['results'] : body;
    return [
      for (final r in (list is List ? list : const []))
        if (r is Map && r['is_active'] != false && '${r['quote_decline_reason_id'] ?? ''}'.isNotEmpty)
          (id: '${r['quote_decline_reason_id']}', name: '${r['name'] ?? ''}'),
    ];
  }

  /// `GET {id}/payment-instructions/` — null when none are set up.
  Future<QuotePaymentInstructions?> paymentInstructions(String id) async =>
      QuotePaymentInstructions.fromResponse(await _api.get(_q(id, 'payment-instructions/'), quiet: true));

  /// `GET quotations/?search=<base number>` — candidate rows for the newest
  /// revision of a chain.
  Future<List<Map<String, dynamic>>> searchQuotes(String search) async {
    final body = await _api.get(ApiEndpoints.quotations, query: {'search': search, 'page': 1, 'page_size': 50}, quiet: true);
    final list = body is Map ? body['results'] : body;
    return [for (final r in (list is List ? list : const [])) if (r is Map) Map<String, dynamic>.from(r)];
  }

  /// A lead's / customer's `reference` ("LD-0025" / "CUST-0002"), '' if unknown.
  Future<String> reference(String path) async {
    try {
      final body = await _api.get(path, quiet: true);
      final r = body is Map ? '${body['reference'] ?? ''}' : '';
      return r == 'null' ? '' : r;
    } on Object {
      return '';
    }
  }

  /// `PATCH quotations/{id}/` — a field edit, or a status move with
  /// `status_id` (+ `decline_reason`/`decline_note`, `accepted_on`, `schedule`).
  Future<void> patch(String id, Map<String, dynamic> body) => _api.patch(ApiEndpoints.quotation(id), body: body);

  /// `DELETE quotations/{id}/` — 409 `QUOTE_HAS_PAYMENTS` when paid.
  Future<void> delete(String id) => _api.delete(ApiEndpoints.quotation(id));

  Map<String, dynamic> _row(Object? body) => body is Map ? Map<String, dynamic>.from(body) : const {};

  /// `POST {id}/revise/` → the new draft revision.
  Future<Map<String, dynamic>> revise(String id) async => _row(await _api.post(_q(id, 'revise/'), body: const {}));

  /// `POST {id}/duplicate/` → the new draft.
  Future<Map<String, dynamic>> duplicate(String id) async => _row(await _api.post(_q(id, 'duplicate/'), body: const {}));

  /// `POST {id}/renew/ {valid_until?}` → the new revision at today's prices.
  Future<Map<String, dynamic>> renew(String id, String? validUntil) async => _row(await _api.post(_q(id, 'renew/'),
      body: validUntil == null || validUntil.isEmpty ? const {} : {'valid_until': validUntil}));

  /// `GET {id}/render/?output=pdf` — the PDF bytes (auth attached).
  Future<List<int>> pdf(String id) async => (await _api.getBytes(_q(id, 'render/?output=pdf'))).$1;

  /// `GET /sales-content/documents/templates/`.
  Future<List<DocTemplate>> documentTemplates() async => DocTemplate.listFrom(await _api.get(docTemplatesPath, quiet: true));

  /// `POST /sales-content/documents/generate/`.
  Future<Map<String, dynamic>> generateDocument(Map<String, dynamic> body) async =>
      _row(await _api.post(generateDocPath, body: body));
}
