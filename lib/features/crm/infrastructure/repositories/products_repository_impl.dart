import '../../../../app/config/constants.dart';
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
}
