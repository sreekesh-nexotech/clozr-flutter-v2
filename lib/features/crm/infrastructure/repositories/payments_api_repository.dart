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
      final rows = await _remote.fetchInvoiceHeaderRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return paymentsFromInvoiceRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(AppCache.crmCache, _cacheKey);
        final data = cached?.data;
        if (data is List) return paymentsFromInvoiceRows(data);
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
