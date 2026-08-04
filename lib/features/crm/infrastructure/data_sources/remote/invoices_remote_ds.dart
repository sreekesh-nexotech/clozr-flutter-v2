import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
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
  Future<List<Map<String, dynamic>>> fetchInvoiceRows() async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 3) {
      final body = await _api.get(ApiEndpoints.payments, query: {
        'page': page,
        'page_size': ApiConfig.defaultPageSize,
      });
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      out.addAll(paged.results);
      if (!paged.hasMore) break;
      page++;
    }
    return out;
  }
}

// ── JSON → entity mapping (public so the repository and tests reuse it) ──

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
      of++;
      final st = r['status'];
      if (st is String && st.toLowerCase() == 'paid') settled++;
    }
    return Invoice(
      id: id,
      custId: _str(row['customer_id']) ??
          (row['customer'] is Map ? _str((row['customer'] as Map)['customer_id']) : null),
      quoteId: quotationNumber,
      type: _str(row['payment_type']) == 'lumpsum' ? 'Lump sum' : 'Installments',
      total: formatInr(total),
      totalNum: total.round(),
      settled: settled,
      of: of,
      balance: formatInr(parseAmount(row['amount_remaining'])),
      status: invoiceStatusKey(status: _str(row['status']), amountPaid: amountPaid),
    );
  } on Object {
    return null;
  }
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
