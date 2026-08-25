import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../domain/entities/product.dart';
import '../providers/products_providers.dart';

/// Products filter — spec-driven drawer wired like the Leads reference (audit §8).
/// Generic drawer (title "Products"). No date and no owner filter.
///
/// Unit price is an **absolute-rupee** number range (unitScale 1), not lakhs.

/// A product's unit price in rupees, for the number-range facet.
///
/// Reads [Product.priceNum], never the display string: `formatInr` abbreviates
/// (₹4,999 renders as "₹5K"), so stripping non-digits off the display yielded
/// **5** for a ₹4,999 product and the range filter compared rupees against a
/// handful. The display parse survives only for rows built without a numeric
/// price, where it is still exact ("₹2,400" → 2400).
int productPriceNum(Product p) {
  if (p.priceNum > 0) return p.priceNum.round();
  final digits = p.price.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}

/// Build the Products drawer spec from the current catalog.
FilterSpec buildProductsFilterSpec(List<Product> products) {
  // Category options mirror the catalog's product categories (audit §8), in the
  // canonical order; excludes the synthetic "Package" category.
  // Anything the catalog actually carries: the built-in names first, in their
  // canonical order, then the org's own. Intersecting with the built-in list
  // alone left the facet **empty** against a live catalog, whose categories
  // ("SaaS Platform", …) are none of the prototype's fit-out words.
  final present = products.map((p) => p.cat).where((c) => c.isNotEmpty).toSet();
  final ordered = <String>[
    for (final c in productCategoryOrder)
      if (present.contains(c)) c,
    ...(present.difference(productCategoryOrder.toSet()).toList()..sort()),
  ];
  final categories = [for (final c in ordered) FilterOption(id: c, label: c)];
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
  // Scoped to the open mode: built from the whole catalog, the Packages
  // drawer offered categories and billing units that only products have, and
  // choosing one emptied the list.
  final wantPackages = ref.watch(prodModeProvider) == 'packages';
  final products = ref
      .watch(allProductsProvider)
      .where((p) => p.isPackage == wantPackages)
      .toList();
  return buildProductsFilterSpec(products);
});

/// Applied drawer filters for the Products list (source of the badge count).
final productFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Products list (bookmark chips).
final productSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
