import '../entities/crm_catalog.dart';
import '../entities/product.dart';
import '../entities/product_usage.dart';

/// Abstract contract for product/catalog data. The presentation layer depends
/// only on this; whether products come from a mock source or a REST API is an
/// infrastructure detail.
abstract class ProductsRepository {
  Future<List<Product>> getProducts();

  /// One catalog item by id. Null when unavailable (mock mode, a failed call),
  /// which callers read as "fall back to the list row".
  Future<Product?> getProduct(String id);

  /// The org's own product categories. Empty when unavailable, which callers
  /// read as "use the built-in category list".
  Future<List<CatalogOption>> getProductTypes();

  /// Partially updates a catalog item — the Activate/Deactivate toggle today.
  /// Returns the updated entity when the backend echoes it, null otherwise.
  Future<Product?> updateProduct(String id, Map<String, dynamic> fields);

  /// Deletes a catalog item. Throws when the backend refuses — a product used
  /// as a package component cannot be removed.
  /// How much this item is used — leads and quotes it appears on. Answers
  /// zero counts on failure, which reads as "no activity".
  Future<ProductUsage> getUsage(String id);

  Future<void> deleteProduct(String id);

  /// Creates a catalog product from the Add-product sheet's [fields]
  /// (`product_name`, `price`, `hsn_code`, `description`, `is_active`).
  /// Returns the created entity when the backend echoes it, null otherwise.
  /// Mock mode echoes a local entity without persisting.
  Future<Product?> createProduct(Map<String, dynamic> fields);
}
