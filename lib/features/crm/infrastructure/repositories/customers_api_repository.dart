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
  Future<List<Customer>> getCustomers({
    Map<String, dynamic> filters = const {},
  }) async {
    try {
      final rows = await _remote.fetchCustomerRows(filters: filters);
      // Only the unfiltered list is cached: a filtered response is a slice, and
      // serving it back offline as "the customers" would silently hide rows.
      if (filters.isEmpty) {
        await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      }
      return CustomersRemoteDataSource.mapCustomerRows(rows);
    } on AppError catch (e) {
      if (e.type != AppErrorType.network && e.type != AppErrorType.timeout) {
        rethrow;
      }
      final cached =
          filters.isEmpty ? AppCache.get(AppCache.crmCache, _cacheKey)?.data : null;
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

  /// Writes are remote-only and drop the cached list so the next read refetches.
  @override
  Future<void> updateCustomer(String id, Map<String, dynamic> fields) async {
    await _remote.updateCustomer(id, fields);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
  }

  @override
  Future<String?> createUpsell(String id) async {
    final leadId = await _remote.createUpsell(id);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    return leadId;
  }

  /// Best-effort: a failure yields the empty list, which callers read as "no org
  /// catalog", so a dead catalog never blocks the status control.
  @override
  Future<List<CustomerStatus>> getCustomerStatuses() async {
    try {
      final rows = await _remote.fetchCustomerStatusRows();
      return [
        for (final row in rows)
          if ((row['customer_status_id'] ?? row['id'])?.toString().isNotEmpty ?? false)
            CustomerStatus(
              id: (row['customer_status_id'] ?? row['id']).toString(),
              name: (row['name'] ?? '').toString(),
              statusType: (row['status_type'] ?? '').toString(),
            ),
      ];
    } on Object {
      return const [];
    }
  }
}
