import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/products_filter_spec.dart';
import '../../application/providers/products_providers.dart';
import '../../domain/entities/product.dart';
import '../components/add_product_sheet.dart';
import '../components/mode_toggle.dart';
import '../components/product_card.dart';
import '../components/saved_chip_row.dart';

/// Products & Services — a Products|Packages mode toggle over a category-tab
/// list of catalog cards, wired to the spec-driven filter engine (drawer →
/// matcher → badge → saved views), mirroring the Leads reference.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(prodSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(prodModeProvider);

    // Contextual add: the bottom-nav `+` opens the Add product/package sheet.
    registerAdd(
      ref,
      AddAction(label: 'Add product', run: (ctx) => showAddProductSheet(ctx, mode: mode)),
    );

    final all = ref.watch(allProductsProvider);
    final async = ref.watch(productsProvider);
    final cat = ref.watch(prodCatProvider);
    final searchOpen = ref.watch(prodSearchOpenProvider);
    final query = ref.watch(prodSearchProvider);
    final filterCount = ref.watch(productFiltersProvider).activeCount;

    final catKeys = ['all', ...productCategoryOrder];

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Products & Services',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () => ref.read(prodSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
            ),
            SizedBox(height: 14.h),
            ModeToggle(
              options: [
                ModeOption(PhosphorIconsRegular.package, 'Products (${prodModeCount(all, 'products')})'),
                ModeOption(PhosphorIconsRegular.stack, 'Packages (${prodModeCount(all, 'packages')})'),
              ],
              selectedIndex: mode == 'products' ? 0 : 1,
              onChanged: (i) {
                ref.read(prodModeProvider.notifier).state = i == 0 ? 'products' : 'packages';
                ref.read(prodCatProvider.notifier).state = 'all';
              },
            ),
            SizedBox(height: 14.h),
            if (searchOpen) ...[
              SearchField(
                controller: _searchCtrl,
                hint: 'Search products, SKU, HSN…',
                onChanged: (v) => ref.read(prodSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(prodSearchProvider.notifier).state = '';
                  ref.read(prodSearchOpenProvider.notifier).state = false;
                },
              ),
              SizedBox(height: 14.h),
            ],
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final k in catKeys)
                    TabChip(
                      label: '${k == 'all' ? 'All' : k} (${prodCatCount(all, k)})',
                      active: cat == k,
                      onTap: () => ref.read(prodCatProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _savedViewRow(filterCount),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<Product>>(
            value: async,
            onRetry: () => ref.invalidate(productsProvider),
            data: (_) {
              final visible = ref.watch(visibleProductsProvider);
              if (visible.isEmpty) {
                return ListView(
                  children: [
                    EmptyState(
                      icon: PhosphorIconsRegular.package,
                      title: 'No items found',
                      body: 'Try a different category, clear filters, or add a catalog item.',
                      ctaLabel: mode == 'packages' ? 'Add package' : 'Add product',
                      ctaIcon: PhosphorIconsBold.plus,
                      onCta: () => showAddProductSheet(context, mode: mode),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                itemCount: visible.length,
                separatorBuilder: (_, __) => SizedBox(height: 10.h),
                itemBuilder: (context, i) {
                  final product = visible[i];
                  return ProductCard(
                    product: product,
                    onTap: () => context.push('${Routes.productDetail}?id=${product.id}'),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    final spec = ref.read(productsFilterSpecProvider);
    final current = ref.read(productFiltersProvider);
    final mode = ref.read(prodModeProvider);
    // Preview within the active mode (Products vs Packages), matching the list.
    final base = ref
        .read(allProductsProvider)
        .where((p) => (mode == 'packages') == p.isPackage)
        .toList();
    final activeView = ref.read(productSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((p) => productMatchesFilters(p, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: (name, draft) {
        ref.read(productSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(productFiltersProvider.notifier).state = result;
    final views = ref.read(productSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(productSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(productSavedViewsProvider);
    return SavedChipRow(
      views: [for (final v in saved.views) SavedView(v.id, v.name)],
      active: {if (saved.activeId != null) saved.activeId!},
      showClearAlways: filterCount > 0,
      onToggle: _toggleView,
      onClear: _clearFilters,
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(productSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(productSavedViewsProvider.notifier).deactivate();
      ref.read(productFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(productSavedViewsProvider.notifier).apply(id);
    ref.read(productFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(productSavedViewsProvider.notifier).clearActive();
    ref.read(productFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
