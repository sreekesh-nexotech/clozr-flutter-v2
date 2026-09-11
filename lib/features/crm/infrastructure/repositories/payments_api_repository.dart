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

  // Payments are flattened from the invoice headers (which embed their
  // records) so each row's invId is the parent's display id — the key the
  // installment-schedule join uses. Cached under the invoices key since it is
  // literally the same `/quotations/payments/` payload.
  static const String _cacheKey = 'invoices';

  @override
  Future<List<Payment>> getPayments() async {
    try {
      // `/quotations/payment-records/`, not the invoice headers.
      //
      // The header *list* does not serialize `records` at all — only the
      // per-invoice detail does — so flattening the list yielded **nothing**:
      // the Payments screen was empty against a backend holding 127 records,
      // and every "next open installment" lookup that reads this list came
      // back null ("No open installments on this invoice").
      //
      // The records endpoint returns them directly, and each row carries its
      // own `quotation_number`, so `invId` stays the display id the invoice
      // join and the Related links expect.
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
  }) async {
    await _remote.markRecordPaid(recordId, amount: amount, method: method);
    // The server recalculates the parent invoice; the payments list and the
    // invoices list share the same cached payload, so one eviction covers both.
    await AppCache.remove(AppCache.crmCache, _cacheKey);
  }
}
