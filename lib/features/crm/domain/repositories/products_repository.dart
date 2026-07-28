import '../entities/product.dart';

/// Abstract contract for product/catalog data. The presentation layer depends
/// only on this; whether products come from a mock source or a REST API is an
/// infrastructure detail.
abstract class ProductsRepository {
  Future<List<Product>> getProducts();
}
