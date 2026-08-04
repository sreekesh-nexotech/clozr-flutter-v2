import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/products_repository.dart';
import '../data_sources/remote/products_remote_ds.dart';

/// API-backed [ProductsRepository]: remote fetch with Hive fallback when the
/// network is down; writes are remote-only and evict the list cache so the
/// next read refetches (guide §2).
class ProductsApiRepository implements ProductsRepository {
  const ProductsApiRepository(this._remote);

  final ProductsRemoteDataSource _remote;

  static const String _cacheKey = 'products';

  @override
  Future<List<Product>> getProducts() async {
    try {
      final rows = await _remote.fetchProductRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return productsFromApiRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(AppCache.crmCache, _cacheKey);
        final data = cached?.data;
        if (data is List) return productsFromApiRows(data);
      }
      rethrow;
    }
  }

  @override
  Future<Product?> createProduct(Map<String, dynamic> fields) async {
    final created = await _remote.createProduct(fields);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    return created;
  }
}
