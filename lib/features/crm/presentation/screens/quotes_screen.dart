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
    _searchCtrl.text = ref.read(quoteSearchProvider);
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
  bool _tabActive(String tab, String chipKey, List<CatalogOption> statuses) {
    if (tab == chipKey) return true;
    for (final s in statuses) {
      if (s.name == chipKey && quoteStatusKey(name: s.name) == tab) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Add quote form on this screen.
    registerAdd(
      ref,
      AddAction(label: 'Add quote', run: (ctx) => ctx.push(Routes.addQuote)),
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
              onSearch: () => ref.read(quoteSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
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
                      onTap: () => ref.read(quoteTabProvider.notifier).state = k,
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
                    EmptyState(
                      icon: PhosphorIconsRegular.fileText,
                      title: 'No quotes found',
                      body: 'Try a different status, clear filters, or create a new quote.',
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
                  return QuoteCard(
                    quote: quote,
                    schema: cardSchema,
                    onTap: () => context.push('${Routes.quoteDetail}?id=${quote.id}'),
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

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(quoteSavedViewsProvider);
    return SavedChipRow(
      views: [for (final v in saved.views) SavedView(v.id, v.name)],
      active: {if (saved.activeId != null) saved.activeId!},
      showClearAlways: filterCount > 0,
      onToggle: _toggleView,
      onClear: _clearFilters,
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(quoteSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(quoteSavedViewsProvider.notifier).deactivate();
      ref.read(quoteFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(quoteSavedViewsProvider.notifier).apply(id);
    ref.read(quoteFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(quoteSavedViewsProvider.notifier).clearActive();
    ref.read(quoteFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
