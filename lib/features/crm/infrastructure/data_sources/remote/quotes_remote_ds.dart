import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/quote.dart';
import '../../../domain/entities/view_schema.dart';
import '../../../domain/repositories/quotes_repository.dart';

/// Raw quotation endpoints — HTTP + JSON→entity mapping only. Caching lives in
/// the API repository above this layer.
class QuotesRemoteDataSource {
  const QuotesRemoteDataSource(this._api);

  final ApiService _api;

  /// Raw `/quotations/quotations/` rows, following `next` up to 3 pages. The
  /// repository caches these and maps them via [quotesFromApiRows].
  Future<List<Map<String, dynamic>>> fetchQuoteRows() => _fetchRows();

  /// Raw rows for the quotes raised against one lead. Unlike tasks and call
  /// logs, quotations carry a real `lead` FK, so the filter is a plain
  /// `?lead=<lead_id>` rather than the generic-relation pair.
  Future<List<Map<String, dynamic>>> fetchQuoteRowsForLead(String leadId) =>
      _fetchRows(leadId: leadId);

  Future<List<Map<String, dynamic>>> _fetchRows({String? leadId}) async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 50) {
      final body = await _api.get(ApiEndpoints.quotations, query: {
        'page': page,
        'page_size': ApiConfig.defaultPageSize,
        if (leadId != null) 'lead': leadId,
      });
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      out.addAll(paged.results);
      if (!paged.hasMore) break;
      page++;
    }
    return out;
  }

  /// The org's Quote layout, used to drive the New quote form.
  ///
  /// **`view_type=detail`, deliberately — not `form`.** `template`, `lead`,
  /// `owner` and `line_items` are serializer fields, not model fields, and
  /// `?view_type=form` introspects model fields only, so it returns none of
  /// them. `detail` is the only call that describes the whole form.
  ///
  /// Best-effort: any failure yields the empty schema, which the form reads as
  /// "show every field I know how to render".
  Future<ViewSchema> fetchQuoteSchema() async {
    try {
      final body = await _api.get(
        ApiEndpoints.quotationSchema,
        query: {'view_type': 'detail'},
      );
      return ViewSchema.fromResponse(body);
    } on Object {
      return ViewSchema.empty;
    }
  }

  /// The org's quote templates, as `(id, name)` options for the picker.
  /// Best-effort — an empty list means the form omits the picker and lets the
  /// server apply the org's default template.
  Future<List<QuoteTemplate>> fetchTemplates() async {
    try {
      final body = await _api.get(
        ApiEndpoints.quotationTemplates,
        query: {'page_size': 100, 'is_active': true},
      );
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      final out = <QuoteTemplate>[];
      for (final row in rows) {
        final id = _str(row['template_id']);
        // The list serializer names it `template_name`; `name` is accepted as
        // an alternate shape.
        final name = _str(row['template_name']) ?? _str(row['name']);
        if (id == null || name == null) continue;
        out.add(QuoteTemplate(
          id: id,
          name: name,
          isDefault: row['is_default'] == true,
        ));
      }
      return out;
    } on Object {
      return const [];
    }
  }

  /// `POST /quotations/quotations/` — creates a quote.
  ///
  /// [fields] is sent as-is: the caller has already shaped it to the API's
  /// contract (`lead`, `payment_type`, `line_items`, …). `owner` and `customer`
  /// are deliberately never included — the server stamps the owner as the
  /// creating user, and a quote only gains a customer if its lead converts.
  ///
  /// Returns the created quote, or null when the response is not a row we can
  /// map (never a crash).
  Future<Quote?> createQuote(Map<String, dynamic> fields) async {
    final body = await _api.post(ApiEndpoints.quotations, body: fields);
    if (body is! Map<String, dynamic>) return null;
    try {
      return quoteFromApi(body);
    } on Object {
      return null;
    }
  }
}
// ── JSON → entity mapping (public so the repository and tests reuse it) ──

/// Maps a list of raw rows, skipping malformed entries.
List<Quote> quotesFromApiRows(List<dynamic> rows) {
  final out = <Quote>[];
  for (final r in rows) {
    if (r is Map<String, dynamic>) {
      final q = quoteFromApi(r);
      if (q != null) out.add(q);
    }
  }
  return out;
}

/// Maps one `/quotations/quotations/` row → [Quote]. Returns null when the row
/// is unusable (no id) — a malformed row is skipped, never fatal.
Quote? quoteFromApi(Map<String, dynamic> row) {
  final id = _str(row['quotation_number']) ?? _str(row['quotation_id']);
  if (id == null) return null;
  try {
    final statusRaw = row['status'];
    final statusName =
        statusRaw is Map ? _str(statusRaw['name']) : _str(statusRaw);
    final validUntil = parseApiDate(row['valid_until']);
    final total = parseAmount(row['total_amount']);
    return Quote(
      id: id,
      custId: _str(row['customer_id']) ?? _linkedId(row['customer'], 'customer_id'),
      leadId: _linkedId(row['lead'], 'lead_id') ?? _str(row['lead_id']),
      status: quoteStatusKey(
        name: statusName,
        validUntil: validUntil,
        isConverted: row['is_converted'] == true,
      ),
      amount: formatInr(total),
      amountNum: total.round(),
      issued: absoluteDate(parseApiDate(row['created_at'])),
      valid: absoluteDate(validUntil),
      template: _str(row['template']) ?? 'Standard',
      payType: _payTypeDisplay(row['payment_type'] ?? row['pay_type']),
      currency: _str(row['currency']) ?? 'INR',
      dueDate: absoluteDate(parseApiDate(row['next_due_date'] ?? row['due_date'])),
      owner: _ownerId(row),
      items: _items(row['items'] ?? row['line_items']),
      note: _str(row['notes']) ?? _str(row['note']),
    );
  } on Object {
    return null;
  }
}

List<QuoteItem> _items(Object? raw) {
  if (raw is! List) return const [];
  final out = <QuoteItem>[];
  for (final m in raw) {
    if (m is! Map) continue;
    final qty = _int(m['quantity']) ?? _int(m['qty']) ?? 1;
    final rate = parseAmount(m['unit_price'] ?? m['price'] ?? m['rate']);
    final amtRaw = m['amount'] ?? m['total'] ?? m['line_total'] ?? m['subtotal'];
    final amt = amtRaw != null ? parseAmount(amtRaw) : rate * qty;
    out.add(QuoteItem(
      name: _str(m['product_name']) ?? _str(m['name']) ?? _str(m['description']) ?? 'Item',
      qty: qty,
      rate: formatInr(rate),
      amt: formatInr(amt),
    ));
  }
  return out;
}

String _payTypeDisplay(Object? v) {
  final s = v is String ? v.toLowerCase() : '';
  return s.contains('install') ? 'Installments' : 'Lump sum';
}

String _ownerId(Map<String, dynamic> row) {
  for (final key in const ['owner', 'created_by']) {
    final v = row[key];
    if (v is Map) {
      UserDirectory.registerJson(v);
      final id = _str(v['user_id']);
      if (id != null) return UserDirectory.mapUserId(id);
    } else if (v is String && v.isNotEmpty) {
      return UserDirectory.mapUserId(v);
    }
  }
  return '';
}

String? _linkedId(Object? v, String idKey) {
  if (v is Map) return _str(v[idKey]);
  return _str(v);
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

int? _int(Object? v) => v is num ? v.toInt() : null;
