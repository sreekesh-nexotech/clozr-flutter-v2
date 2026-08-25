import '../../../../app/config/constants.dart';
import '../../../../core/utils/inr_format.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/products_repository.dart';
import '../data_sources/local/products_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one when the
/// API lands — the interface and every caller stay the same.
class ProductsRepositoryImpl implements ProductsRepository {
  const ProductsRepositoryImpl(this._local);

  final ProductsMockDataSource _local;

  @override
  Future<List<Product>> getProducts() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchProducts();
  }

  /// No per-product endpoint in mock mode; null keeps the screen on the seed
  /// row.
  @override
  Future<Product?> getProduct(String id) async => null;

  /// No category catalog in mock mode; empty keeps the built-in chip list.
  @override
  Future<List<CatalogOption>> getProductTypes() async => const [];

  /// Mock write: no-op — the catalog seed is immutable here.
  @override
  Future<Product?> updateProduct(String id, Map<String, dynamic> fields) async => null;

  /// Mock write: no-op — the catalog seed is immutable here.
  @override
  Future<void> deleteProduct(String id) async {}

  @override
  Future<Product?> createProduct(Map<String, dynamic> fields) async {
    // Mock mode: echo a local entity — the sheet inserts via its own
    // manualProductsProvider path, so nothing is persisted here.
    await Future<void>.delayed(AppConstants.mockLatency);
    final name = fields['product_name'] as String? ?? '';
    if (name.isEmpty) return null;
    final price = fields['price'] is num ? (fields['price'] as num).toDouble() : 0.0;
    return Product(
      id: 'NEW-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      kind: 'product',
      cat: '',
      hsn: fields['hsn_code'] as String? ?? '',
      unit: '',
      price: formatInr(price),
      priceNum: price,
      gst: 18,
      gstAmt: formatInr(price * 0.18),
      gross: formatInr(price * 1.18),
      deals: 0,
      revenue: '₹0',
      revNum: 0,
      avg: '—',
      active: fields['is_active'] != false,
      desc: fields['description'] as String?,
    );
  }
}
