import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/models/note.dart';
import '../../../notes/application/providers/notes_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/products_repository.dart';
import '../../infrastructure/data_sources/local/products_mock_ds.dart';
import '../../infrastructure/data_sources/remote/products_remote_ds.dart';
import '../../infrastructure/repositories/products_api_repository.dart';
import '../../infrastructure/repositories/products_repository_impl.dart';
import '../filters/products_filter_spec.dart';
export '../products_counts.dart';

/// DI seam: mock-backed without a base URL, API-backed otherwise.
final productsRepositoryProvider = Provider<ProductsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const ProductsRepositoryImpl(ProductsMockDataSource());
  }
  return ProductsApiRepository(
    ProductsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Async source of all catalog products/packages.
final productsProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(productsRepositoryProvider).getProducts(),
);

/// One catalog item, read directly (`GET /crm/products/{id}/`).
///
/// The detail screen prefers this over the list row: it is one call, and a
/// product outside the loaded pages still opens. Null in mock mode and on
/// failure. Watches the write tick so an edit made elsewhere lands here.
final productDetailProvider =
    FutureProvider.autoDispose.family<Product?, String>((ref, id) {
  ref.watch(apiWriteTickProvider);
  return ref.watch(productsRepositoryProvider).getProduct(id);
});

/// The org's own product categories (`GET /crm/product-types/`).
final productTypeCatalogProvider = FutureProvider<List<CatalogOption>>(
  (ref) => ref.watch(productsRepositoryProvider).getProductTypes(),
);

/// Synchronous view of the category catalog; empty means "use the built-in
/// [productCategoryOrder] list" (mock mode, or an org with no types).
final productTypeOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(productTypeCatalogProvider).valueOrNull ?? const [],
);

/// The category chips on the Products list: the org's own categories when it
/// has any, the prototype's fixed set otherwise.
final productCategoriesProvider = Provider<List<String>>((ref) {
  final live = ref.watch(productTypeOptionsProvider);
  return live.isEmpty ? productCategoryOrder : [for (final c in live) c.name];
});

/// A product's Notes card (`GET /crm/notes/?related_to=product&…`).
///
/// The notes panel is polymorphic, and `related_to=product` is a live pair
/// (verified against the dev backend) — the entity's own `notes` list is always
/// empty because no product endpoint carries one. Empty in mock mode and on
/// failure, which the card renders as "no notes". Read-only for now: the
/// composer still only toasts.
final productNotesProvider =
    FutureProvider.autoDispose.family<List<NoteEntry>, String>((ref, id) async {
  if (!ApiConfig.apiEnabled || id.isEmpty) return const [];
  ref.watch(apiWriteTickProvider);
  try {
    return await ref.read(notesRepositoryProvider).fetchNotes('product', id);
  } on Object {
    return const [];
  }
});

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
    // The field the search box promises ("products, SKU, HSN") is the SKU —
    // `p.id` is the uuid, which nobody types. Category is included because the
    // chips only offer one at a time.
    out = out.where((p) =>
        ('${p.name} ${p.code} ${p.hsn} ${p.cat} ${p.id}').toLowerCase().contains(q));
  }
  return out.toList();
});

