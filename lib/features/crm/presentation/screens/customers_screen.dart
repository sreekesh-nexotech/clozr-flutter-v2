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
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/customers_filter_spec.dart';
import '../../application/providers/customers_providers.dart';
import '../../domain/entities/customer.dart';
import '../components/customer_card.dart';
import '../components/saved_chip_row.dart' as chips;
import '../sheets/add_customer_sheet.dart';

/// Customers list — same header + tabs + card-list pattern as Leads, now wired
/// to the spec-driven filter engine (drawer → applied provider → matcher →
/// badge → saved views) and the contextual Add customer sheet.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(customerSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Add customer sheet here.
    registerAdd(
      ref,
      AddAction(label: 'Add customer', run: (ctx) => showAddCustomerSheet(ctx, ref)),
    );

    final all = ref.watch(customersAllProvider);
    final async = ref.watch(customersProvider);
    final tab = ref.watch(customerTabProvider);
    final searchOpen = ref.watch(customerSearchOpenProvider);
    final query = ref.watch(customerSearchProvider);
    final filterCount = ref.watch(customerFiltersProvider).activeCount;

    final tabDefs = <(String, String?)>[
      ('all', null),
      for (final k in StatusMeta$.customerOrder) (k, k),
    ];

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Customers',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () => ref.read(customerSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search customers…',
                onChanged: (v) => ref.read(customerSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(customerSearchProvider.notifier).state = '';
                  ref.read(customerSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 10.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final (k, dotKey) in tabDefs)
                    TabChip(
                      label: '${_label(k)} (${customerTabCount(all, k)})',
                      active: tab == k,
                      dotColor: dotKey == null ? null : StatusMeta$.customer[dotKey]!.color,
                      onTap: () => ref.read(customerTabProvider.notifier).state = k,
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
          child: AsyncStateView<List<Customer>>(
            value: async,
            onRetry: () => ref.invalidate(customersProvider),
            data: (_) {
              final visible = ref.watch(visibleCustomersProvider);
              if (visible.isEmpty) {
                return ListView(
                  children: [
                    EmptyState(
                      icon: PhosphorIconsRegular.userCircle,
                      title: 'No customers found',
                      body: 'Try a different status, clear filters, or add a new customer.',
                      ctaLabel: 'Add customer',
                      ctaIcon: PhosphorIconsBold.plus,
                      onCta: () => showAddCustomerSheet(context, ref),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                itemCount: visible.length,
                separatorBuilder: (_, __) => SizedBox(height: 14.h),
                itemBuilder: (context, i) {
                  final c = visible[i];
                  return CustomerCard(
                    customer: c,
                    onTap: () => context.push('${Routes.customerDetail}?id=${c.id}'),
                    onCall: () => ref.read(toastProvider.notifier).show('Calling ${c.name.split(' ').first}…'),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _label(String key) => key == 'all' ? 'All' : StatusMeta$.customer[key]!.label;

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    final spec = ref.read(customersFilterSpecProvider);
    final current = ref.read(customerFiltersProvider);
    final base = ref.read(customersAllProvider);
    final activeView = ref.read(customerSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((c) => customerMatchesFilters(c, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: (name, draft) {
        ref.read(customerSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(customerFiltersProvider.notifier).state = result;
    final views = ref.read(customerSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(customerSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(customerSavedViewsProvider);
    return SizedBox(
      height: 34.h,
      child: chips.SavedChipRow(
        views: [for (final v in saved.views) chips.SavedView(v.id, v.name)],
        active: {if (saved.activeId != null) saved.activeId!},
        showClearAlways: filterCount > 0,
        onToggle: _toggleView,
        onClear: _clearFilters,
      ),
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(customerSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(customerSavedViewsProvider.notifier).deactivate();
      ref.read(customerFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(customerSavedViewsProvider.notifier).apply(id);
    ref.read(customerFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(customerSavedViewsProvider.notifier).clearActive();
    ref.read(customerFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
