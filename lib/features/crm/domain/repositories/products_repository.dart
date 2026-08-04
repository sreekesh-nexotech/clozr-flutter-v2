import '../entities/product.dart';

/// Abstract contract for product/catalog data. The presentation layer depends
/// only on this; whether products come from a mock source or a REST API is an
/// infrastructure detail.
abstract class ProductsRepository {
  Future<List<Product>> getProducts();

  /// Creates a catalog product from the Add-product sheet's [fields]
  /// (`product_name`, `price`, `hsn_code`, `description`, `is_active`).
  /// Returns the created entity when the backend echoes it, null otherwise.
  /// Mock mode echoes a local entity without persisting.
  Future<Product?> createProduct(Map<String, dynamic> fields);
}
