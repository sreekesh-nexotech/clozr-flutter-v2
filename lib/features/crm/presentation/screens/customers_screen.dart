import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/customers_filter_spec.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/saved_filters_providers.dart';
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
    // The org's mobile card layout: which of the card's slots to render. Empty
    // until it loads (and in mock mode), which the card reads as "use the
    // built-in layout" — so the list never waits on this call.
    final cardSchema = ref.watch(customerListSchemaProvider);
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
            onRefresh: _refresh,
            data: (_) {
              final visible = ref.watch(visibleCustomersProvider);
              if (visible.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
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
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                itemCount: visible.length,
                separatorBuilder: (_, __) => SizedBox(height: 14.h),
                itemBuilder: (context, i) {
                  final c = visible[i];
                  return CustomerCard(
                    customer: c,
                    schema: cardSchema,
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
  /// Pull-to-refresh: the customer rows and the saved views over them.
  Future<void> _refresh() async {
    ref.invalidate(customersProvider);
    ref.invalidate(customerListSchemaFutureProvider);
    await settle([
      ref.read(customersProvider.future),
      ref.read(customerListSchemaFutureProvider.future),
    ]);
  }

  /// Pull the drawer's option catalogs before opening it — the sheet takes its
  /// spec once and keeps it, so a half-loaded catalog would be snapshotted.
  /// Normally already resolved (the fetches start at mount), so this yields for
  /// a microtask and no more.
  Future<void> _openFilters() async {
    await ref.read(customerFilterCatalogsProvider.future);
    if (!mounted) return;

    // Counted against the scope with the drawer filters dropped: a draft usually
    // widens the current selection, and counting inside the already filtered
    // list could only ever count down. Falls back to the visible rows if that
    // fetch fails — the preview is an estimate, never a blocker.
    List<Customer> previewBase;
    try {
      previewBase = await ref
          .read(customersScopedProvider(ref.read(customersUnfilteredQueryProvider)).future);
    } on Object {
      previewBase = ref.read(customersAllProvider);
    }
    if (!mounted) return;

    final spec = ref.read(customersFilterSpecProvider);
    final current = ref.read(customerFiltersProvider);
    final activeView = ref.read(customerSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      // Still the local matcher: a live count per keystroke cannot be a round
      // trip. Apply is authoritative — that is what re-queries the server.
      previewCount: (draft) =>
          previewBase.where((c) => customerMatchesFilters(c, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: _saveView,
    );
    if (result == null) return;

    _applyFilters(result);
    // A manual Apply deactivates the active saved view unless the draft still
    // means the same thing. Compared as encoded definitions, since that is what
    // the view actually stores.
    final active = ref.read(customerSavedViewsProvider).active;
    if (active != null) {
      final encoded = ref.read(customerFilterCodecProvider).encode(result);
      if (!sameFilterDefinition(encoded, active.definition)) {
        ref.read(customerSavedViewsProvider.notifier).deactivate();
      }
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  /// Applies a filter set to the list.
  ///
  /// The query it is about to watch is dropped first, so re-applying a
  /// combination fetched earlier really re-queries instead of serving the list
  /// as it looked then.
  void _applyFilters(FilterValues values) {
    final params =
        customerFilterParamsFor(values, ref.read(customerFilterCodecProvider));
    ref.invalidate(customersScopedProvider(CustomerListQuery(filters: params)));
    ref.read(customerFiltersProvider.notifier).state = values;
  }

  /// Persists the drawer draft as a saved filter. The API stores the backend's
  /// own param dict, so the draft is encoded before it is sent; server-side
  /// rejections (duplicate name, 5-per-module limit) come back as user-safe text
  /// and are shown as-is.
  Future<void> _saveView(String name, FilterValues draft) async {
    final definition = ref.read(customerFilterCodecProvider).encode(draft);
    final error =
        await ref.read(customerSavedViewsProvider.notifier).save(name, definition);
    if (!mounted) return;
    ref.read(toastProvider.notifier).show(error ?? 'View "$name" saved');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(customerSavedViewsProvider);
    return SizedBox(
      height: 34.h,
      child: chips.SavedChipRow(
        views: [for (final f in saved.filters) chips.SavedView(f.id, f.name)],
        active: {if (saved.activeId != null) saved.activeId!},
        showClearAlways: filterCount > 0,
        onToggle: _toggleView,
        onClear: _clearFilters,
      ),
    );
  }

  Future<void> _toggleView(String id) async {
    final saved = ref.read(customerSavedViewsProvider);
    if (saved.activeId == id) {
      // Tapping the active view deactivates it and clears the applied filters.
      ref.read(customerSavedViewsProvider.notifier).deactivate();
      _applyFilters(FilterValues());
      return;
    }
    final view = saved.filters.firstWhere((f) => f.id == id);
    // A filter the server marked invalid (it references a purged custom field)
    // fails inert by contract — never run it, say why instead.
    if (!view.isValid) {
      ref.read(toastProvider.notifier).show(
            'View "${view.name}" refers to a field that no longer exists.',
          );
      return;
    }
    // A chip is tappable without ever opening the drawer, so wait for the same
    // catalogs here: decoding maps stored server ids back to drawer options.
    await ref.read(customerFilterCatalogsProvider.future);
    if (!mounted) return;

    final values = ref
        .read(customerFilterCodecProvider)
        .decode(view.definition, ref.read(customersFilterSpecProvider));
    ref.read(customerSavedViewsProvider.notifier).apply(id);
    _applyFilters(values);
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(customerSavedViewsProvider.notifier).deactivate();
    _applyFilters(FilterValues());
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
