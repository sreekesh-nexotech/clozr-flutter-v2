/// The Products screen's tab and chip counts.
///
/// Kept out of the providers file, which reaches phosphor through the category
/// glyph map and so cannot be imported from a test under this toolchain.
library;

import '../domain/entities/product.dart';

/// Count of items in a category, within the open mode — the category chip
/// label.
///
/// [mode] is `products` | `packages`. It used to be hardcoded to the product
/// side, so every chip in the Packages tab counted the products behind it.
int prodCatCount(List<Product> products, String key, {String mode = 'products'}) {
  final wantPackages = mode == 'packages';
  return products
      .where((p) => p.isPackage == wantPackages && (key == 'all' || p.cat == key))
      .length;
}

/// Count of items for a mode ('products' | 'packages') — the mode tab label.
int prodModeCount(List<Product> products, String mode) =>
    products.where((p) => (mode == 'packages') == p.isPackage).length;
