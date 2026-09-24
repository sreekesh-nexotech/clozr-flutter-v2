import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/payment.dart';
import '../../domain/repositories/payments_repository.dart';
import '../data_sources/remote/payments_remote_ds.dart';

/// API-backed [PaymentsRepository]: remote fetch with Hive fallback when the
/// network is down; writes are remote-only and evict the affected list caches
/// so the next read refetches (guide §2).
class PaymentsApiRepository implements PaymentsRepository {
  const PaymentsApiRepository(this._remote);

  final PaymentsRemoteDataSource _remote;

  // Its own key. This used to share `'invoices'` with the invoices repository
  // from when both read the same `/quotations/payments/` payload; now that
  // payments come from `payment-records/`, the two lists would have kept
  // overwriting each other's offline copy with rows the other mapper cannot
  // read.
  static const String _cacheKey = 'payment_records';

  /// The invoices repository's key — `markRecordPaid` evicts it too, because
  /// the server recalculates the parent invoice on every settlement.
  static const String _invoicesCacheKey = 'invoices';

  @override
  Future<List<Payment>> getPayments() async {
    try {
      // `/quotations/payment-records/`, not the invoice headers.
      //
      // The header *list* does not serialize `records` at all — only the
      // per-invoice detail does — so flattening the list yielded **nothing**:
      // the Payments screen was empty against a backend holding 127 records,
      // and every "next open installment" lookup that reads this list came
      // back null ("No open installments on this invoice"). The backend has
      // since confirmed `payment-records/` as the collection for "all
      // installments", so this is the contract, not a workaround.
      //
      // Each row carries its own `quotation_number`, so `invId` stays the
      // display id the invoice join and the Related links expect.
      final rows = await _remote.fetchPaymentRecordRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return paymentsFromApiRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(AppCache.crmCache, _cacheKey);
        final data = cached?.data;
        if (data is List) return paymentsFromApiRows(data);
      }
      rethrow;
    }
  }

  @override
  Future<void> markRecordPaid(
    String recordId, {
    double? amount,
    String method = 'upi',
    double? tdsDeducted,
    double? bankCharge,
  }) async {
    await _remote.markRecordPaid(recordId,
        amount: amount,
        method: method,
        tdsDeducted: tdsDeducted,
        bankCharge: bankCharge);
    // The server recalculates the parent invoice (amount_paid, next_due_date,
    // completion), so both offline copies are stale.
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    await AppCache.remove(AppCache.crmCache, _invoicesCacheKey);
  }
}
