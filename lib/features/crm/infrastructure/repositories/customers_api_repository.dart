import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customers_repository.dart';
import '../data_sources/remote/customers_remote_ds.dart';

/// API-backed [CustomersRepository]. Reads cache the raw JSON rows and serve
/// them back when the network is unreachable; writes are remote-only and drop
/// the cached list so the next read refetches.
class CustomersApiRepository implements CustomersRepository {
  const CustomersApiRepository(this._remote);

  final CustomersRemoteDataSource _remote;

  static const String _cacheKey = 'customers';

  @override
  Future<List<Customer>> getCustomers() async {
    try {
      final rows = await _remote.fetchCustomerRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return CustomersRemoteDataSource.mapCustomerRows(rows);
    } on AppError catch (e) {
      if (e.type != AppErrorType.network && e.type != AppErrorType.timeout) {
        rethrow;
      }
      final cached = AppCache.get(AppCache.crmCache, _cacheKey)?.data;
      if (cached is List) {
        return CustomersRemoteDataSource.mapCustomerRows(cached);
      }
      rethrow;
    }
  }

  @override
  Future<Customer?> createCustomer(Map<String, dynamic> fields) async {
    final customer = await _remote.createCustomer(fields);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    return customer;
  }
}
