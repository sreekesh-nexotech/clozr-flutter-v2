import 'package:intl/intl.dart';

import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../domain/entities/payment.dart';

/// Raw payment-record endpoints. `/quotations/payment-records/` rows ARE the
/// UI's payments (installment rows). HTTP + JSON→entity mapping only —
/// caching lives in the API repository.
class PaymentsRemoteDataSource {
  const PaymentsRemoteDataSource(this._api);

  final ApiService _api;

  /// Raw `/quotations/payment-records/` rows, following `next` up to 3 pages.
  /// The repository caches these and maps them via [paymentsFromApiRows].
  Future<List<Map<String, dynamic>>> fetchPaymentRecordRows() async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 3) {
      final body = await _api.get(ApiEndpoints.paymentRecords, query: {
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

  /// Raw `/quotations/payments/` invoice-header rows (each embeds its full
  /// `records` list), following `next` up to 3 pages. Payments are flattened
  /// from these via [paymentsFromInvoiceRows] so each record's `invId` carries
  /// the parent's display id (`quotation_number`) — the same value the Invoice
  /// mapper uses for `Invoice.id`, so the installment-schedule join lines up.
  Future<List<Map<String, dynamic>>> fetchInvoiceHeaderRows() async {
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

  /// Settles one record: `PATCH /quotations/payment-records/{id}/`. The server
  /// recalculates the parent invoice (amount_paid, next_due_date, completion),
  /// so callers must refetch both lists afterwards.
  Future<void> markRecordPaid(
    String recordId, {
    double? amount,
    String method = 'upi',
  }) async {
    await _api.patch(ApiEndpoints.paymentRecord(recordId), body: {
      'status': 'paid',
      if (amount != null) 'amount_paid': amount.toStringAsFixed(2),
      'paid_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'payment_method': method,
    });
  }
}

// ── JSON → entity mapping (public so the repository and tests reuse it) ──

/// Maps a list of raw `/quotations/payment-records/` rows, skipping malformed
/// and cancelled entries. Here each record's `invId` is the parent's uuid.
List<Payment> paymentsFromApiRows(List<dynamic> rows) {
  final out = <Payment>[];
  for (final r in rows) {
    if (r is Map<String, dynamic>) {
      final p = paymentRecordFromApi(r);
      if (p != null) out.add(p);
    }
  }
  return out;
}

/// Flattens `/quotations/payments/` invoice-header rows into the flat payment
/// list, stamping each embedded record's `invId` with the parent's display id
/// (`quotation_number`, matching [Invoice.id]) so the installment-schedule
/// join in `paymentsForInvoiceProvider` resolves.
List<Payment> paymentsFromInvoiceRows(List<dynamic> invoiceRows) {
  final out = <Payment>[];
  for (final inv in invoiceRows) {
    if (inv is! Map<String, dynamic>) continue;
    final parentId = _str(inv['quotation_number']) ?? _str(inv['payment_id']);
    final records = inv['records'];
    if (records is! List) continue;
    for (final r in records) {
      if (r is! Map<String, dynamic>) continue;
      final p = paymentRecordFromApi(r, invIdOverride: parentId);
      if (p != null) out.add(p);
    }
  }
  return out;
}

/// Maps one `/quotations/payment-records/` row → [Payment]. Returns null for
/// unusable (no id) and `cancelled` rows — both are skipped, never fatal.
/// [invIdOverride] stamps the parent's display id when flattening from an
/// invoice header (the record itself only carries the parent uuid).
Payment? paymentRecordFromApi(Map<String, dynamic> row, {String? invIdOverride}) {
  final id = _str(row['record_id']);
  if (id == null) return null;
  final rawStatus = _str(row['status']);
  if ((rawStatus ?? '').toLowerCase() == 'cancelled') return null;
  try {
    final due = parseApiDate(row['due_date']);
    final paid = parseApiDate(row['paid_date']);
    final paidAmt = parseAmount(row['amount_paid']);
    final amount = paidAmt > 0 ? paidAmt : parseAmount(row['amount_expected']);
    final statusKey = paymentStatusKey(status: rawStatus, dueDate: due);
    final installmentNumber = row['installment_number'];
    return Payment(
      id: id,
      custId: _str(row['customer_id']),
      invId: invIdOverride ?? _str(row['invoice_id']),
      label: _str(row['notes']) ??
          'Installment ${installmentNumber is num ? installmentNumber.toInt() : 1}',
      amount: formatInr(amount),
      amountNum: amount.round(),
      method: paymentMethodDisplay(row['payment_method']),
      status: statusKey,
      date: paid != null
          ? absoluteDate(paid)
          : (statusKey == 'overdue'
              ? 'Overdue ${absoluteDate(due)}'
              : absoluteDate(due)),
      owner: '',
    );
  } on Object {
    return null;
  }
}

/// API `payment_method` code → the UI's display string.
String paymentMethodDisplay(Object? code) {
  switch (code is String ? code.toLowerCase() : '') {
    case 'bank_transfer':
      return 'Bank transfer';
    case 'upi':
      return 'UPI';
    case 'card':
      return 'Card';
    case 'cash':
      return 'Cash';
    case 'cheque':
      return 'Cheque';
    default:
      return '—';
  }
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
