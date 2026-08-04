import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/repositories/invoices_repository.dart';
import '../data_sources/remote/invoices_remote_ds.dart';

/// API-backed [InvoicesRepository]: remote fetch with Hive fallback when the
/// network is down (guide §2: cache raw rows, map on read).
class InvoicesApiRepository implements InvoicesRepository {
  const InvoicesApiRepository(this._remote);

  final InvoicesRemoteDataSource _remote;

  static const String _cacheKey = 'invoices';

  @override
  Future<List<Invoice>> getInvoices() async {
    try {
      final rows = await _remote.fetchInvoiceRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return invoicesFromApiRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(AppCache.crmCache, _cacheKey);
        final data = cached?.data;
        if (data is List) return invoicesFromApiRows(data);
      }
      rethrow;
    }
  }
}
