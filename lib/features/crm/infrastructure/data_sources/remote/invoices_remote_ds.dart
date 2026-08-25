import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../domain/entities/invoice.dart';

/// Raw payment-header endpoints. `/quotations/payments/` rows ARE the UI's
/// invoices (a `Payment` is auto-created when a quote is accepted). HTTP +
/// JSON→entity mapping only — caching lives in the API repository.
class InvoicesRemoteDataSource {
  const InvoicesRemoteDataSource(this._api);

  final ApiService _api;

  /// Raw `/quotations/payments/` rows, following `next` up to 3 pages. The
  /// repository caches these and maps them via [invoicesFromApiRows].
  Future<List<Map<String, dynamic>>> fetchInvoiceRows({
    String? customerId,
  }) async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 50) {
      final body = await _api.get(ApiEndpoints.payments, query: {
        'page': page,
        'page_size': ApiConfig.defaultPageSize,
        // Payment → Quotation → Customer; the server walks the chain.
        if (customerId != null) 'customer_id': customerId,
      });
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      out.addAll(paged.results);
      if (!paged.hasMore) break;
      page++;
    }
    return out;
  }

  /// `GET /quotations/payments/{payment_id}/summary/` (doc §2b).
  ///
  /// Best-effort: the header row already carries enough to render the invoice,
  /// so a failure here means the screen keeps its own arithmetic rather than
  /// losing the card. Returns null on any failure, which callers read as "no
  /// server figures — use the derived ones".
  Future<InvoiceSummary?> fetchSummary(String paymentId) async {
    if (paymentId.isEmpty) return null;
    try {
      final body = await _api.get(ApiEndpoints.paymentSummary(paymentId));
      return body is Map<String, dynamic> ? summaryFromApi(body) : null;
    } on Object {
      return null;
    }
  }
}

// ── JSON → entity mapping (public so the repository and tests reuse it) ──

/// Maps the `summary` payload. Amounts arrive as decimal **strings**
/// (`"184991.00"`), so they go through the same `parseAmount` as every other
/// money field rather than being read as numbers.
InvoiceSummary summaryFromApi(Map<String, dynamic> row) => InvoiceSummary(
      totalNum: parseAmount(row['total_amount']).round(),
      paidNum: parseAmount(row['amount_paid']).round(),
      remainingNum: parseAmount(row['amount_remaining']).round(),
      currency: _str(row['currency']) ?? 'INR',
      status: _str(row['status']) ?? '',
      nextDue: parseApiDate(row['next_due_date']),
      totalRecords: _int(row['total_records']),
      pendingRecords: _int(row['pending_records']),
      paidRecords: _int(row['paid_records']),
      overdueRecords: _int(row['overdue_records']),
    );

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Maps a list of raw rows, skipping malformed entries.
List<Invoice> invoicesFromApiRows(List<dynamic> rows) {
  final out = <Invoice>[];
  for (final r in rows) {
    if (r is Map<String, dynamic>) {
      final iv = invoiceFromApi(r);
      if (iv != null) out.add(iv);
    }
  }
  return out;
}

/// Maps one `/quotations/payments/` row → [Invoice]. Returns null when the row
/// is unusable (no id) — a malformed row is skipped, never fatal.
Invoice? invoiceFromApi(Map<String, dynamic> row) {
  final quotationNumber = _str(row['quotation_number']);
  final id = quotationNumber ?? _str(row['payment_id']);
  if (id == null) return null;
  try {
    final total = parseAmount(row['total_amount']);
    final amountPaid = parseAmount(row['amount_paid']);
    final records =
        row['records'] is List ? (row['records'] as List) : const <dynamic>[];
    var settled = 0;
    var of = 0;
    for (final r in records) {
      if (r is! Map) continue;
      final st = r['status'];
      final statusStr = st is String ? st.toLowerCase() : '';
      // Cancelled records aren't part of the schedule (paymentRecordFromApi
      // drops them too), so they must not inflate "settled X of Y".
      if (statusStr == 'cancelled') continue;
      of++;
      if (statusStr == 'paid') settled++;
    }
    return Invoice(
      id: id,
      uuid: _str(row['payment_id']) ?? '',
      custId: _str(row['customer_id']) ??
          (row['customer'] is Map ? _str((row['customer'] as Map)['customer_id']) : null),
      quoteId: quotationNumber,
      quoteUuid: _str(row['quotation']),
      type: _str(row['payment_type']) == 'lumpsum' ? 'Lump sum' : 'Installments',
      total: formatInr(total),
      totalNum: total.round(),
      settled: settled,
      of: of,
      balance: formatInr(parseAmount(row['amount_remaining'])),
      paidNum: amountPaid.round(),
      status: invoiceStatusKey(status: _str(row['status']), amountPaid: amountPaid),
    );
  } on Object {
    return null;
  }
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
