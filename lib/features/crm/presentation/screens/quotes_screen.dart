import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/quotes_filter_spec.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/quotes_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/quote.dart';
import '../components/quote_card.dart';
import '../components/quote_discount_approval.dart';
import '../components/saved_chip_row.dart';

/// Quotes list — status-tab list of quote cards over the standard list header,
/// wired to the spec-driven filter engine (drawer → matcher → badge → saved
/// views), mirroring the Leads reference.
class QuotesScreen extends ConsumerStatefulWidget {
  const QuotesScreen({super.key});

  @override
  ConsumerState<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends ConsumerState<QuotesScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // A query left behind by a collapsed box would filter the list with
    // nothing on screen saying so; only keep it while the box is open.
    if (!ref.read(quoteSearchOpenProvider) && ref.read(quoteSearchProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(quoteSearchProvider.notifier).state = '';
      });
    } else {
      _searchCtrl.text = ref.read(quoteSearchProvider);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Whether a chip should read as selected.
  ///
  /// Tolerant on purpose: the catalog can land after the user has already
  /// picked a built-in key, swapping "Draft" for the org's own status. Matching
  /// the folded key as well keeps that chip highlighted through the swap
  /// instead of leaving the row with nothing selected.
  bool _tabActive(Set<String> chips, String chipKey, List<CatalogOption> statuses) {
    if (chipKey == 'all') return chips.isEmpty;
    if (chips.contains(chipKey)) return true;
    for (final s in statuses) {
      if (s.name == chipKey && chips.contains(quoteStatusKey(name: s.name))) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Add quote form on this screen.
    registerAdd(
      ref,
      AddAction(label: 'Add quote', module: 'quotation', run: (ctx) => ctx.push(Routes.addQuote)),
    );

    final async = ref.watch(quotesProvider);
    // The org's mobile card layout. Empty until it loads (and in mock mode),
    // which the card reads as "use the built-in layout".
    final cardSchema = ref.watch(quoteListSchemaProvider);
    final all = async.valueOrNull ?? const [];
    final tab = ref.watch(quoteTabProvider);
    final searchOpen = ref.watch(quoteSearchOpenProvider);
    final query = ref.watch(quoteSearchProvider);
    final filterCount = ref.watch(quoteFiltersProvider).activeCount;

    // The org's own statuses drive the tab row — names, order and colour, in the
    // server's `position` order (doc §4). Empty (mock mode, still loading,
    // failed fetch) falls back to the built-in five, the same "empty is no
    // opinion" contract the Leads and Tasks tab rows use.
    //
    // Counted client-side on purpose: the doc's Gaps section records that
    // `/quotations/` has no `status-counts` action, so there is nothing to read
    // a facet from.
    final statuses = ref.watch(quoteStatusOptionsProvider);
    // Counting reads the same key set the chips below are built from, so a row
    // is listed under exactly the tab whose number claimed it.
    final tabKeys = ref.watch(quoteTabKeysProvider);
    final tabs = <(String, String)>[
      ('all', 'All'),
      if (statuses.isEmpty)
        for (final k in const ['draft', 'sent', 'accepted', 'rejected', 'expired'])
          (k, StatusMeta$.quote[k]!.label)
      else
        for (final s in statuses) (s.name, s.name),
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
              title: 'Quotes',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () {
                // Collapsing the box drops the query, like clearing the webapp's
                // search box — a hidden query would keep narrowing the list.
                if (searchOpen) {
                  _searchCtrl.clear();
                  ref.read(quoteSearchProvider.notifier).state = '';
                }
                ref.read(quoteSearchOpenProvider.notifier).state = !searchOpen;
              },
              onFilter: _openFilters,
              trailing: _toolbarActions(),
            ),
            if (searchOpen) ...[
              SizedBox(height: 12.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search quotes…',
                onChanged: (v) => ref.read(quoteSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(quoteSearchProvider.notifier).state = '';
                  ref.read(quoteSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 10.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final (k, lbl) in tabs)
                    TabChip(
                      label: '$lbl (${quoteTabCount(all, k, tabKeys: tabKeys)})',
                      active: _tabActive(tab, k, statuses),
                      // Multi-select like the webapp: chips add up, All clears.
                      onTap: () => ref.read(quoteTabProvider.notifier).update(
                            (cur) => toggleQuoteChip(cur, k),
                          ),
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
          child: AsyncStateView<List<Quote>>(
            value: async,
            onRetry: () => ref.invalidate(quotesProvider),
            onRefresh: _refresh,
            data: (_) {
              final visible = ref.watch(visibleQuotesProvider);
              if (visible.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _isNarrowed()
                        ? EmptyState(
                            icon: PhosphorIconsRegular.funnel,
                            title: 'No quotes match your filters',
                            body: 'Try widening your search or clearing a filter to see more.',
                            ctaLabel: 'Clear filters',
                            ctaIcon: PhosphorIconsBold.xCircle,
                            onCta: _resetListView,
                          )
                        : EmptyState(
                            icon: PhosphorIconsRegular.fileText,
                            title: 'No quotes yet',
                            body: 'Quotes let you send priced proposals to your leads and customers. Create your first one to get started.',
                            ctaLabel: 'Add quote',
                            ctaIcon: PhosphorIconsBold.plus,
                            onCta: () => context.push(Routes.addQuote),
                          ),
                  ],
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                itemCount: visible.length,
                separatorBuilder: (_, __) => SizedBox(height: 10.h),
                itemBuilder: (context, i) {
                  final quote = visible[i];
                  // Long-press offers the webapp row's actions (View, Delete).
                  return GestureDetector(
                    onLongPress: () => _rowActions(quote),
                    child: QuoteCard(
                      quote: quote,
                      schema: cardSchema,
                      onTap: () => context.push('${Routes.quoteDetail}?id=${quote.id}'),
                    ),
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
  /// Pull-to-refresh: the quote rows.
  Future<void> _refresh() async {
    ref.invalidate(quotesProvider);
    ref.invalidate(quoteListSchemaFutureProvider);
    // The tab row is the org's status list, so a refresh has to pick up a
    // status an admin added or renamed since the screen mounted.
    ref.invalidate(quoteStatusCatalogProvider);
    await settle([
      ref.read(quotesProvider.future),
      ref.read(quoteListSchemaFutureProvider.future),
      ref.read(quoteStatusCatalogProvider.future),
    ]);
  }

  Future<void> _openFilters() async {
    final spec = ref.read(quotesFilterSpecProvider);
    final current = ref.read(quoteFiltersProvider);
    final base = ref.read(quotesProvider).valueOrNull ?? const [];
    final activeView = ref.read(quoteSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base
          .where((q) => quoteMatchesFilters(q, draft, ref.read(crmPartyLookupProvider)))
          .length,
      activeViewName: activeView?.name,
      existingViewNames: ref.read(quoteSavedViewsProvider).views.map((v) => v.name).toSet(),
      onSaveView: (name, draft) {
        ref.read(quoteSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(quoteFiltersProvider.notifier).state = result;
    final views = ref.read(quoteSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(quoteSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  /// Deletes a saved view after the chip's confirm. Removing the applied view
  /// also clears its filters.
  void _removeView(String id) {
    final wasActive = ref.read(quoteSavedViewsProvider).activeId == id;
    ref.read(quoteSavedViewsProvider.notifier).remove(id);
    if (wasActive) ref.read(quoteFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('View removed');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(quoteSavedViewsProvider);
    return SavedChipRow(
      views: [for (final v in saved.views) SavedView(v.id, v.name)],
      active: {if (saved.activeId != null) saved.activeId!},
      showClearAlways: filterCount > 0,
      onToggle: _toggleView,
      onClear: _clearFilters,
      onRemove: _removeView,
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(quoteSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(quoteSavedViewsProvider.notifier).deactivate();
      ref.read(quoteFiltersProvider.notifier).state = FilterValues();
      return;
    }
    // The chip was built from an earlier snapshot of the saved-view list. If
    // the view was deleted or renamed elsewhere between render and tap,
    // `firstWhere` threw a StateError inside a tap handler - a red screen in
    // debug, a swallowed tap in release. Fail inert and say so instead.
    final view = saved.views.where((v) => v.id == id).firstOrNull;
    if (view == null) {
      ref.read(toastProvider.notifier).show('That view is no longer available.');
      return;
    }
    ref.read(quoteSavedViewsProvider.notifier).apply(id);
    ref.read(quoteFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  /// Whether a search, status chip or drawer filter is narrowing the list —
  /// the webapp then says "match your filters" instead of "yet".
  bool _isNarrowed() =>
      ref.read(quoteSearchProvider).trim().isNotEmpty ||
      ref.read(quoteFiltersProvider).activeCount > 0 ||
      ref.read(quoteTabProvider).isNotEmpty;

  /// The empty state's "Clear filters": search, chip and drawer back to all.
  void _resetListView() {
    _searchCtrl.clear();
    ref.read(quoteSearchProvider.notifier).state = '';
    ref.read(quoteTabProvider.notifier).state = const {};
    _clearFilters();
  }

  void _clearFilters() {
    ref.read(quoteSavedViewsProvider.notifier).clearActive();
    ref.read(quoteFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }

  // ── Toolbar: discount approvals, win / loss report, Grand total sort ──
  Widget _toolbarActions() {
    final sort = ref.watch(quoteSortProvider);
    final pending = ref.watch(quoteDiscountApprovalsBadgeProvider).valueOrNull ?? 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _toolbarIcon(
        icon: sort.isEmpty
            ? PhosphorIconsRegular.arrowsDownUp
            : sort.startsWith('-')
                ? PhosphorIconsBold.sortDescending
                : PhosphorIconsBold.sortAscending,
        tip: 'Sort by Grand total',
        active: sort.isNotEmpty,
        onTap: () {
          final next = nextQuoteSort(ref.read(quoteSortProvider));
          ref.read(quoteSortProvider.notifier).state = next;
          ref.read(toastProvider.notifier).show(switch (next) {
            '-grand_total' => 'Sorted by Grand total (high → low)',
            'grand_total' => 'Sorted by Grand total (low → high)',
            _ => 'Sort cleared',
          });
        },
      ),
      _toolbarIcon(
        icon: PhosphorIconsRegular.sealCheck,
        tip: pending > 0
            ? 'Discount approvals — $pending waiting for you'
            : 'Discount approvals',
        badge: pending > 0 ? '$pending' : null,
        onTap: () async {
          await context.push(Routes.quoteApprovals);
          if (mounted) {
            ref.invalidate(quoteDiscountApprovalsBadgeProvider);
            ref.invalidate(quotesProvider);
          }
        },
      ),
      _toolbarIcon(
        icon: PhosphorIconsRegular.chartBar,
        tip: 'Win / loss report',
        onTap: () => context.push(Routes.quoteWinLoss),
      ),
    ]);
  }

  Widget _toolbarIcon({
    required IconData icon,
    required String tip,
    required VoidCallback onTap,
    String? badge,
    bool active = false,
  }) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 36.w,
          height: 38.w,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon,
                  size: 20.sp,
                  color: active ? AppColors.navy : AppColors.textSecondary),
              if (badge != null)
                Positioned(
                  top: 3.h,
                  right: 1.w,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(badge,
                        style: TextStyle(
                            color: Colors.white, fontSize: 9.sp, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Row actions: the webapp row's View / Delete ──
  Future<void> _rowActions(Quote quote) async {
    final canDelete = hasPermission(ref, 'quotation', PermVerb.delete);
    await showActionMenu(context, title: quote.id, actions: [
      MenuAction(
        icon: PhosphorIconsRegular.eye,
        label: 'View',
        onTap: () => context.push('${Routes.quoteDetail}?id=${quote.id}'),
      ),
      if (canDelete)
        MenuAction(
          icon: PhosphorIconsRegular.trash,
          label: 'Delete',
          destructive: true,
          // An accepted / paid quote has a plan the server will not delete
          // (409 QUOTE_HAS_PAYMENTS) — shown disabled with the reason, as on web.
          enabled: !quote.isDeleteBlocked,
          sublabel: quote.isDeleteBlocked
              ? "Accepted or paid quotes can't be deleted — cancel or credit-note in accounting first"
              : null,
          onTap: () => _confirmDelete(quote),
        ),
    ]);
  }

  Future<void> _confirmDelete(Quote quote) async {
    final ok = await confirmDeleteQuote(context, quote.id);
    if (!ok || !mounted) return;
    try {
      await ref.read(apiServiceProvider).delete(ApiEndpoints.quotation(quote.uuid));
    } on AppError catch (e) {
      if (mounted) ref.read(toastProvider.notifier).showError(e.bareMessage);
      return;
    }
    if (!mounted) return;
    ref.read(toastProvider.notifier).show('${quote.id} deleted');
    ref.invalidate(quotesProvider);
  }
}

/// The webapp's "Delete this quote?" confirm — shared by the list row and the
/// detail screen.
Future<bool> confirmDeleteQuote(BuildContext context, String number) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this quote?'),
      content: Text(
          "${number.isEmpty ? 'This quote' : number} and its unpaid payment plan will be deleted. "
          "A quote whose plan has a recorded payment, a receipt or an invoice can't be deleted."),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Delete quote', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  return ok == true;
}
