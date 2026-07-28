import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/products_providers.dart';
import '../components/mode_toggle.dart';
import '../components/product_card.dart';
import '../components/saved_chip_row.dart';

/// Products & Services — a Products|Packages mode toggle over a category-tab
/// list of catalog cards.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _searchCtrl = TextEditingController();

  static const _savedViews = [
    SavedView('ptop', 'Top earners'),
    SavedView('pact', 'Active only'),
  ];

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
    final all = ref.watch(productsProvider).valueOrNull ?? const [];
    final visible = ref.watch(visibleProductsProvider);
    final mode = ref.watch(prodModeProvider);
    final cat = ref.watch(prodCatProvider);
    final searchOpen = ref.watch(prodSearchOpenProvider);
    final query = ref.watch(prodSearchProvider);
    final saved = ref.watch(prodSavedProvider);

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
              onSearch: () => ref.read(prodSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: () => ref.read(toastProvider.notifier).show('Filters — full CRM filter engine'),
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
            SavedChipRow(
              views: _savedViews,
              active: saved,
              onToggle: (key) {
                final next = {...saved};
                next.contains(key) ? next.remove(key) : next.add(key);
                ref.read(prodSavedProvider.notifier).state = next;
              },
              onClear: () => ref.read(prodSavedProvider.notifier).state = {},
            ),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: visible.isEmpty
              ? ListView(
                  children: const [
                    EmptyState(
                      icon: PhosphorIconsRegular.package,
                      title: 'No items found',
                      body: 'Try a different category or clear filters.',
                    ),
                  ],
                )
              : ListView.separated(
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
                ),
        ),
      ],
    );
  }
}
