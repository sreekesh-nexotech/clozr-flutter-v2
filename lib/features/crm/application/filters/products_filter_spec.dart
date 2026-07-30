import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../domain/entities/product.dart';
import '../providers/products_providers.dart';

/// Products filter — spec-driven drawer wired like the Leads reference (audit §8).
/// Generic drawer (title "Products"). No date and no owner filter.
///
/// Unit price is an **absolute-rupee** number range (unitScale 1), not lakhs.

/// Parse a product's display price ("₹2,400", "₹2,50,000") to rupees.
int productPriceNum(Product p) {
  final digits = p.price.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}

/// Build the Products drawer spec from the current catalog.
FilterSpec buildProductsFilterSpec(List<Product> products) {
  // Category options mirror the catalog's product categories (audit §8), in the
  // canonical order; excludes the synthetic "Package" category.
  final present = products.map((p) => p.cat).toSet();
  final categories = [
    for (final c in productCategoryOrder)
      if (present.contains(c)) FilterOption(id: c, label: c),
  ];
  final statuses = const [
    FilterOption(id: 'active', label: 'Active'),
    FilterOption(id: 'inactive', label: 'Inactive'),
  ];
  // Distinct billing units in the catalog (admin-configurable list).
  final units = (products.map((p) => p.unit).where((u) => u.isNotEmpty).toSet().toList()..sort())
      .map((u) => FilterOption(id: u, label: u))
      .toList();

  return FilterSpec(
    title: 'Products',
    sections: [
      FilterSection(title: 'Catalog', fields: [
        FilterField(
            id: 'category',
            label: 'Category',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: categories),
        FilterField(
            id: 'status',
            label: 'Status',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: statuses),
        FilterField(
            id: 'billingUnit',
            label: 'Billing unit',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: units),
      ]),
      FilterSection(title: 'Pricing', fields: [
        const FilterField(
            id: 'unitPrice',
            label: 'Unit price',
            control: FilterControl.numberRange,
            unit: '₹',
            unitScale: 1),
      ]),
    ],
  );
}

/// Evaluate a product against applied filter values.
bool productMatchesFilters(Product p, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('category'), [p.cat])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('status'), [p.active ? 'active' : 'inactive'])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('billingUnit'), [p.unit])) return false;
  if (!FilterMatch.matchRange(v.range('unitPrice'), productPriceNum(p), scale: 1)) return false;
  return true;
}

// ── Providers ──

/// The Products drawer spec, derived from the loaded catalog.
final productsFilterSpecProvider = Provider<FilterSpec>((ref) {
  final products = ref.watch(allProductsProvider);
  return buildProductsFilterSpec(products);
});

/// Applied drawer filters for the Products list (source of the badge count).
final productFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Products list (bookmark chips).
final productSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
