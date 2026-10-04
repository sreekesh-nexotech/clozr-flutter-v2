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
/// UI's payments (installment rows) — the backend has confirmed it as the
/// collection for "all installments"; the `/quotations/payments/` header list
/// deliberately does not embed `records`. HTTP + JSON→entity mapping only —
/// caching lives in the API repository.
class PaymentsRemoteDataSource {
  const PaymentsRemoteDataSource(this._api);

  final ApiService _api;

  /// Raw `/quotations/payment-records/` rows, following `next` up to 3 pages.
  /// The repository caches these and maps them via [paymentsFromApiRows].
  Future<List<Map<String, dynamic>>> fetchPaymentRecordRows() async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 50) {
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

  /// Settles one record: `PATCH /quotations/payment-records/{id}/`. The server
  /// recalculates the parent invoice (amount_paid, next_due_date, completion),
  /// so callers must refetch both lists afterwards.
  ///
  /// [amountPaid] is the **cash** received, net of TDS and bank charge — the
  /// withheld parts count toward settlement server-side. [tdsDeducted] and
  /// [bankCharge] are only accepted in a PATCH that also sends
  /// `status: 'paid'`, which this one does. Amounts are the API's decimal
  /// strings, so no paise are lost.
  ///
  /// With accounting active, the same transaction posts a receipt. Money
  /// source resolution needs [bankAccountId] for any non-cash method unless
  /// the org has a default bank, or it is refused with 409
  /// `NO_BANK_ACCOUNT_FOR_METHOD` and the record is left unpaid (handover
  /// §9.1). [treatAs] (`ADVANCE` / `CUSTOMER_CREDIT`) only matters when there
  /// is no issued invoice to allocate to.
  ///
  /// Returns whether the refreshed record carries a posted receipt.
  Future<bool> markRecordPaid(
    String recordId, {
    String? amountPaid,
    String method = 'upi',
    DateTime? paidDate,
    String? tdsDeducted,
    String? bankCharge,
    String? bankAccountId,
    String? treatAs,
    String? gatewayRef,
  }) async {
    bool nonZero(String? v) => v != null && (double.tryParse(v) ?? 0) > 0;
    final res = await _api.patch(ApiEndpoints.paymentRecord(recordId), body: {
      'status': 'paid',
      if (amountPaid != null) 'amount_paid': amountPaid,
      // The customer's date, not today's — a receipt posts into the period
      // the money actually arrived in.
      'paid_date': DateFormat('yyyy-MM-dd').format(paidDate ?? DateTime.now()),
      'payment_method': method,
      if (nonZero(tdsDeducted)) 'tds_deducted': tdsDeducted,
      if (nonZero(bankCharge)) 'bank_charge': bankCharge,
      if (bankAccountId != null) 'bank_account_id': bankAccountId,
      if (treatAs != null) 'treat_as': treatAs,
      if (gatewayRef != null && gatewayRef.isNotEmpty) 'gateway_ref': gatewayRef,
    });
    return res is Map && res['posted_receipt_id'] != null;
  }
}

// ── JSON → entity mapping (public so the repository and tests reuse it) ──

/// Maps a list of raw `/quotations/payment-records/` rows, skipping malformed
/// and cancelled entries.
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

/// Maps one `/quotations/payment-records/` row → [Payment]. Returns null for
/// unusable (no id) and `cancelled` rows — both are skipped, never fatal.
Payment? paymentRecordFromApi(Map<String, dynamic> row) {
  final id = _str(row['record_id']);
  if (id == null) return null;
  final rawStatus = _str(row['status']);
  if ((rawStatus ?? '').toLowerCase() == 'cancelled') return null;
  try {
    final due = parseApiDate(row['due_date']);
    final paid = parseApiDate(row['paid_date']);
    final paidAmt = parseAmount(row['amount_paid']);
    // The **contracted** figure. This used to prefer `amount_paid` once the
    // record was paid, which reads the net cash - so an instalment settled
    // with tax withheld showed a smaller number beside a "Paid" pill and
    // the schedule stopped summing to the invoice total.
    final expected = parseAmount(row['amount_expected']);
    final amount = expected > 0 ? expected : paidAmt;
    final tds = parseAmount(row['tds_deducted']);
    final gstTds = parseAmount(row['gst_tds_deducted']);
    final gstTcs = parseAmount(row['gst_tcs_deducted']);
    final bankCharge = parseAmount(row['bank_charge']);
    final statusKey = paymentStatusKey(status: rawStatus, dueDate: due);
    final installmentNumber = row['installment_number'];
    return Payment(
      id: id,
      custId: _str(row['customer_id']),
      // The list serializer sends only `customer_name`.
      custName: _str(row['customer_name']),
      // The parent's **display** id, because `invId` is shown on screen
      // ("Invoice · QTN-00005"), routed on, and joined against `Invoice.id`.
      // A `payment-records` row carries `quotation_number` itself, so the
      // uuid in `invoice_id` is only a last resort.
      invId: _str(row['quotation_number']) ?? _str(row['invoice_id']),
      // The durable FK to the parent plan. `invoice_id` above is
      // deprecated and goes away one release after accounting ships.
      planUuid: _str(row['payment']),
      label: _str(row['notes']) ??
          'Installment ${installmentNumber is num ? installmentNumber.toInt() : 1}',
      amount: formatInr(amount),
      amountNum: amount.round(),
      paidCashNum: paidAmt.round(),
      tdsNum: tds.round(),
      gstTdsNum: gstTds.round(),
      gstTcsNum: gstTcs.round(),
      bankChargeNum: bankCharge.round(),
      amountExact: _money(row['amount_expected']) ?? _money(row['amount_paid']) ?? '',
      linkedDocumentId: _str(row['linked_document_id']),
      postedReceiptId: _str(row['posted_receipt_id']),
      recordSummary: recordSummaryFromApi(row['record_summary']),
      treatAs: _str(row['treat_as']),
      bankAccountId: _str(row['bank_account_id']),
      gatewayRef: _str(row['gateway_ref']),
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

/// A money field as its exact decimal string, whether sent as text or number.
String? _money(Object? v) {
  if (v is num) return v.toStringAsFixed(2);
  return _str(v);
}

/// `record_summary` → [RecordSummary], or null when absent (accounting off,
/// or nothing linked yet — the two are indistinguishable by design).
RecordSummary? recordSummaryFromApi(Object? v) {
  if (v is! Map) return null;
  final doc = v['document'];
  final rec = v['receipt'];
  final d = doc is Map ? doc : const {};
  final r = rec is Map ? rec : const {};
  final summary = RecordSummary(
    documentId: _str(d['document_id']),
    documentNumber: _str(d['number']),
    documentStatus: _str(d['status']),
    documentPaymentState: _str(d['payment_state']),
    documentOpenBalance: _money(d['open_balance']),
    receiptId: _str(r['receipt_id']),
    receiptStatus: _str(r['status']),
    receiptAmount: _money(r['amount']),
    receiptDate: _str(r['receipt_date']),
  );
  return summary.hasDocument || summary.hasReceipt ? summary : null;
}
