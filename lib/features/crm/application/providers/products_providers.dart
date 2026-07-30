import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/products_repository.dart';
import '../../infrastructure/data_sources/local/products_mock_ds.dart';
import '../../infrastructure/repositories/products_repository_impl.dart';
import '../filters/products_filter_spec.dart';

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final productsRepositoryProvider = Provider<ProductsRepository>(
  (ref) => const ProductsRepositoryImpl(ProductsMockDataSource()),
);

/// Async source of all catalog products/packages.
final productsProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(productsRepositoryProvider).getProducts(),
);

/// Catalog items added in-session via the "Add product" sheet (#14). Prepended
/// to the seed catalog; replaced by the API on integration.
final manualProductsProvider = StateProvider<List<Product>>((ref) => const []);

/// All catalog items = session additions + seed catalog. The single source the
/// list and drawer read from.
final allProductsProvider = Provider<List<Product>>((ref) {
  final seed = ref.watch(productsProvider).valueOrNull ?? const [];
  final manual = ref.watch(manualProductsProvider);
  return [...manual, ...seed];
});

/// Look up a single product by id (detail screen).
final productByIdProvider = Provider.family<Product?, String>((ref, id) {
  final products = ref.watch(allProductsProvider);
  for (final p in products) {
    if (p.id == id) return p;
  }
  return null;
});

/// Ordered catalog categories (excludes the synthetic "Package" category, which
/// belongs to the Packages mode), matching the prototype's `PRODCAT` keys.
const List<String> productCategoryOrder = [
  'Fit-out',
  'Furniture',
  'Design Services',
  'Joinery',
  'MEP & Services',
  'AMC / Maintenance',
];

/// The prototype's `PRODCAT` colour map.
Color productCategoryColor(String cat) {
  switch (cat) {
    case 'Fit-out':
      return AppColors.blueBright;
    case 'Furniture':
      return AppColors.teal;
    case 'Design Services':
      return AppColors.pending;
    case 'Joinery':
      return AppColors.warningDeep;
    case 'MEP & Services':
      return AppColors.navy;
    case 'AMC / Maintenance':
      return AppColors.success;
    case 'Package':
      return AppColors.navyMid;
    default:
      return AppColors.textMuted;
  }
}

/// The prototype's `PRODICON` glyph map.
IconData productCategoryIcon(String cat) {
  switch (cat) {
    case 'Fit-out':
      return PhosphorIconsRegular.squaresFour;
    case 'Furniture':
      return PhosphorIconsRegular.armchair;
    case 'Design Services':
      return PhosphorIconsRegular.penNib;
    case 'Joinery':
      return PhosphorIconsRegular.hammer;
    case 'MEP & Services':
      return PhosphorIconsRegular.plugsConnected;
    case 'AMC / Maintenance':
      return PhosphorIconsRegular.wrench;
    default:
      return PhosphorIconsRegular.package;
  }
}

// ── Products screen UI state ──

/// Mode toggle: 'products' | 'packages'.
final prodModeProvider = StateProvider<String>((ref) => 'products');
final prodCatProvider = StateProvider<String>((ref) => 'all');
final prodSearchProvider = StateProvider<String>((ref) => '');
final prodSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Products filtered by mode + category + drawer filters + search.
final visibleProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(allProductsProvider);
  final mode = ref.watch(prodModeProvider);
  final cat = ref.watch(prodCatProvider);
  final filters = ref.watch(productFiltersProvider);
  final q = ref.watch(prodSearchProvider).trim().toLowerCase();

  Iterable<Product> out =
      products.where((p) => (mode == 'packages') == p.isPackage);
  if (cat != 'all') out = out.where((p) => p.cat == cat);
  if (!filters.isEmpty) out = out.where((p) => productMatchesFilters(p, filters));
  if (q.isNotEmpty) {
    out = out.where((p) => ('${p.name} ${p.id} ${p.hsn}').toLowerCase().contains(q));
  }
  return out.toList();
});

/// Count of products (non-package) in a given category — the category tab label.
int prodCatCount(List<Product> products, String key) {
  return products
      .where((p) => !p.isPackage && (key == 'all' || p.cat == key))
      .length;
}

/// Count of items for a mode ('products' | 'packages') — the mode tab label.
int prodModeCount(List<Product> products, String mode) {
  return products.where((p) => (mode == 'packages') == p.isPackage).length;
}
