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
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/leads_filter_spec.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/lead_schema_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../application/providers/saved_filters_providers.dart';
import '../../domain/entities/lead.dart';
import '../components/lead_card.dart';
import '../components/saved_chip_row.dart' as chips;

/// Leads list — the reference CRM list screen. Header (brand + title + search +
/// filter + status tabs + saved-view row) over a scrolling card list. This is
/// also the reference wiring for the spec-driven filter engine
/// (`lib/core/filters/`): drawer → applied provider → matcher → badge →
/// saved views.
class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Coming back to Leads: the rows, card layout and stages were loaded on an
    // earlier visit and would otherwise be shown as they were then. Re-fetch
    // them, keeping the current cards on screen until the fresh ones arrive.
    // Skipped on the first visit, whose fetches are already in flight.
    if (ref.read(leadsListProvider).hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(leadsScopedProvider);
        ref.invalidate(leadListSchemaFutureProvider);
        ref.invalidate(leadStatusCatalogProvider);
      });
    }
    // A query left behind by a collapsed box would filter the list with
    // nothing on screen saying so; only keep it while the box is open.
    if (!ref.read(leadSearchOpenProvider) && ref.read(leadSearchProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(leadSearchProvider.notifier).state = '';
      });
    } else {
      _searchCtrl.text = ref.read(leadSearchProvider);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Add lead form on this screen.
    registerAdd(
      ref,
      AddAction(label: 'Add lead', module: 'lead', run: (ctx) => ctx.push(Routes.addLead)),
    );

    final async = ref.watch(leadsListProvider);
    final tab = ref.watch(leadTabProvider);
    final searchOpen = ref.watch(leadSearchOpenProvider);
    final query = ref.watch(leadSearchProvider);
    final filterCount = ref.watch(leadFiltersProvider).activeCount;

    final tabBase = ref.watch(leadSearchedProvider);
    // The org's own pipeline stages when `/crm/lead-statuses/` has loaded,
    // otherwise the built-in vocabulary. Name and dot colour both come from
    // the catalog, so the row looks unchanged but reads the org's stages.
    final tabDefs = ref.watch(leadTabsProvider);
    final archived = ref.watch(leadArchivedProvider);
    final lanes = {for (final t in tabDefs) if (t.id != 'all') t.id};
    // Webapp: board total minus the lanes' sum — leads in no known stage.
    final otherCount = leadTabCount(tabBase, leadOtherTab, lanes: lanes);
    final statuses = ref.watch(leadStatusesProvider);
    // Watched purely to start the drawer's option-list fetches now, at mount.
    // Nothing else on this screen references them, so without this they would
    // not begin loading until the user opened the drawer — and the sheet would
    // snapshot them half-loaded.
    ref.watch(leadFilterCatalogsProvider);
    // The org's own card layout. Empty until it loads (and in mock mode), which
    // the card reads as "use the built-in layout" — so the list never waits on
    // this call.
    final schema = ref.watch(leadListSchemaProvider);

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Leads',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () {
                // Collapsing the box drops the query, like clearing the webapp's
                // search box — a hidden query would keep narrowing the list.
                if (searchOpen) {
                  _searchCtrl.clear();
                  ref.read(leadSearchProvider.notifier).state = '';
                }
                ref.read(leadSearchOpenProvider.notifier).state = !searchOpen;
              },
              onFilter: _openFilters,
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search name, company, product…',
                onChanged: (v) => ref.read(leadSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(leadSearchProvider.notifier).state = '';
                  ref.read(leadSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 10.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  // Multi-select like the webapp: "All" is the empty set and
                  // status chips OR-combine; counts follow search and filters,
                  // never the chip selection.
                  for (final t in tabDefs)
                    TabChip(
                      label: '${t.label} (${leadTabCount(tabBase, t.id)})',
                      active: t.id == 'all' ? tab.isEmpty : tab.contains(t.id),
                      dotColor: t.color,
                      onTap: () => _toggleTab(t.id),
                    ),
                  if (otherCount > 0 || tab.contains(leadOtherTab))
                    TabChip(
                      label: 'Other / no status ($otherCount)',
                      active: tab.contains(leadOtherTab),
                      onTap: () => _toggleTab(leadOtherTab),
                    ),
                  TabChip(
                    label: 'Archived',
                    icon: PhosphorIconsRegular.archive,
                    active: archived,
                    onTap: _toggleArchived,
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
          child: AsyncStateView<List<Lead>>(
            value: async,
            onRetry: () => ref.invalidate(leadsScopedProvider),
            onRefresh: _refresh,
            data: (_) {
              final visible = ref.watch(visibleLeadsProvider);
              if (visible.isEmpty) {
                return ListView(
                  // So the gesture still works with nothing to scroll.
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _isNarrowed() || !archived
                        ? _isNarrowed() ? EmptyState(
                            icon: PhosphorIconsRegular.funnel,
                            title: 'No leads match your filters',
                            body: 'Try widening your search or clearing a filter to see more.',
                            ctaLabel: 'Clear filters',
                            ctaIcon: PhosphorIconsBold.xCircle,
                            onCta: _resetListView,
                          )
                        : EmptyState(
                            icon: PhosphorIconsRegular.magnifyingGlass,
                            title: 'No leads yet',
                            body: 'Leads are the people and companies you\'re selling to. Add your first one to get started.',
                            ctaLabel: 'Add lead',
                            ctaIcon: PhosphorIconsBold.plus,
                            onCta: () => context.push(Routes.addLead),
                          )
                        : EmptyState(
                            icon: PhosphorIconsRegular.archive,
                            title: 'No archived leads',
                            body: 'Leads you archive show up here — and lost leads, if your organization auto-archives them.',
                            ctaLabel: 'Back to active leads',
                            ctaIcon: PhosphorIconsBold.arrowLeft,
                            onCta: _toggleArchived,
                          ),
                  ],
                );
              }
              return ListView.separated(
                // Scrolling the results puts the search keyboard away. Without
                // it the only exit is the search field's own × chip, so the
                // keyboard covered the rows the user had just searched for.
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                itemCount: visible.length,
                separatorBuilder: (_, __) => SizedBox(height: 14.h),
                itemBuilder: (context, i) {
                  final lead = visible[i];
                  return LeadCard(
                    lead: lead,
                    // Resolved here rather than inside the card so the pill and
                    // the tab dot above it always agree on name and colour.
                    status: leadStatusMeta(lead, statuses),
                    schema: schema,
                    onTap: () => context.push('${Routes.leadDetail}?id=${lead.id}'),
                    onCall: () => ref.read(toastProvider.notifier).show('Calling ${lead.name.split(' ').first}…'),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Pull-to-refresh. Takes the rows, the org's vocabularies, the card layout
  /// and the saved views together.
  ///
  /// The catalogs and the schema matter as much as the rows here: both are
  /// fetched once per session and nothing invalidates them, so before this an
  /// admin's change to the pipeline stages or the card layout needed an app
  /// restart to show up.
  Future<void> _refresh() async {
    ref.invalidate(leadsScopedProvider);
    ref.invalidate(leadStatusCatalogProvider);
    ref.invalidate(leadSourceCatalogProvider);
    ref.invalidate(leadListSchemaFutureProvider);
    // The drawer snapshots this once; without dropping it too, a refreshed
    // catalog would not reach the filter options.
    ref.invalidate(leadFilterCatalogsProvider);
    await settle([
      ref.read(leadsListProvider.future),
      ref.read(leadListSchemaFutureProvider.future),
      ref.read(leadStatusCatalogProvider.future),
      // Reloaded through the controller rather than invalidated: the provider
      // also holds which view is active, and that is the user's selection, not
      // server state to be thrown away.
      ref.read(leadSavedFiltersProvider.notifier).load(),
    ]);
  }

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    // The sheet takes its spec once and keeps it, so the option lists must be
    // settled before it opens. Normally already resolved — the fetches started
    // when the screen mounted — so this yields for a microtask and no more.
    await ref.read(leadFilterCatalogsProvider.future);
    if (!mounted) return;

    // Counted against the scope with the drawer filters dropped: the draft
    // usually widens the current selection, and counting inside the already
    // filtered list could only ever count down. Free when nothing is applied —
    // it is the same query the list is showing. Falls back to the visible rows
    // if that fetch fails; the preview is an estimate, never a blocker.
    List<Lead> previewBase;
    try {
      previewBase = await ref
          .read(leadsScopedProvider(ref.read(leadsUnfilteredQueryProvider)).future);
    } on Object {
      previewBase = ref.read(leadBaseProvider);
    }
    if (!mounted) return;

    final spec = ref.read(leadsFilterSpecProvider);
    final current = ref.read(leadFiltersProvider);
    final activeView = ref.read(leadSavedFiltersProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      // Still the local matcher: a live count per keystroke cannot be a round
      // trip. Apply is authoritative — that is what re-queries the server.
      previewCount: (draft) => previewBase.where((l) => leadMatchesFilters(l, draft)).length,
      activeViewName: activeView?.name,
      existingViewNames: ref.read(leadSavedFiltersProvider).filters.map((f) => f.name).toSet(),
      onSaveView: _saveView,
    );
    if (result == null) return;

    _applyFilters(result);
    // A manual Apply deactivates the active saved view unless the draft still
    // means the same thing (prototype `deactivateViews` parity). Compared as
    // encoded definitions, since that is what the view actually stores.
    final active = ref.read(leadSavedFiltersProvider).active;
    if (active != null) {
      final encoded = ref.read(leadFilterCodecProvider).encode(result);
      if (!sameFilterDefinition(encoded, active.definition)) {
        ref.read(leadSavedFiltersProvider.notifier).deactivate();
      }
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  /// Applies a filter set to the list.
  ///
  /// The query it is about to watch is dropped first, so re-applying a
  /// combination that was fetched earlier really re-queries instead of serving
  /// the list as it looked then.
  void _applyFilters(FilterValues values) {
    final params = leadFilterParamsFor(values, ref.read(leadFilterCodecProvider));
    ref.invalidate(leadsScopedProvider(
        leadListQueryFor(params, archived: ref.read(leadArchivedProvider))));
    ref.read(leadFiltersProvider.notifier).state = values;
  }

  /// Persists the drawer draft as a saved filter. The API stores the backend's
  /// own param dict, so the draft is encoded before it is sent; server-side
  /// rejections (duplicate name, 5-per-module limit) come back as user-safe
  /// text and are shown as-is.
  Future<void> _saveView(String name, FilterValues draft) async {
    final definition = ref.read(leadFilterCodecProvider).encode(draft);
    // Saving under an existing name overwrites it — the webapp's "Update".
    final updating = ref
        .read(leadSavedFiltersProvider)
        .filters
        .any((f) => f.name.trim().toLowerCase() == name.trim().toLowerCase());
    final error = await ref.read(leadSavedFiltersProvider.notifier).save(name, definition);
    if (!mounted) return;
    final toast = ref.read(toastProvider.notifier);
    error != null ? toast.showError(error) : toast.show(updating ? 'Filter updated' : 'Filter saved');
  }

  /// Deletes a saved view after the chip's confirm. Removing the applied view
  /// also clears its filters, so the list does not stay narrowed by a view
  /// that no longer exists.
  Future<void> _removeView(String id) async {
    final wasActive = ref.read(leadSavedFiltersProvider).activeId == id;
    final error = await ref.read(leadSavedFiltersProvider.notifier).remove(id);
    if (!mounted) return;
    final toast = ref.read(toastProvider.notifier);
    if (error != null) {
      toast.showError(error);
      return;
    }
    if (wasActive) _applyFilters(FilterValues());
    // The webapp confirms the delete and adds no toast after it.
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(leadSavedFiltersProvider);
    return SizedBox(
      height: 34.h,
      child: Row(
        children: [
          Expanded(
            child: chips.SavedChipRow(
              views: [for (final f in saved.filters) chips.SavedView(f.id, f.name, invalid: !f.isValid)],
              active: {if (saved.activeId != null) saved.activeId!},
              showClearAlways: filterCount > 0,
              onToggle: _toggleView,
              onClear: _clearFilters,
              onRemove: _removeView,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleView(String id) async {
    final saved = ref.read(leadSavedFiltersProvider);
    if (saved.activeId == id) {
      // Tapping the active view deactivates it and clears the applied filters.
      ref.read(leadSavedFiltersProvider.notifier).deactivate();
      _applyFilters(FilterValues());
      return;
    }
    // The chip was built from an earlier snapshot of the saved-view list. If
    // the view was deleted or renamed elsewhere between render and tap,
    // `firstWhere` threw a StateError inside a tap handler - a red screen in
    // debug, a swallowed tap in release. Fail inert and say so instead.
    final view = saved.filters.where((f) => f.id == id).firstOrNull;
    if (view == null) {
      ref.read(toastProvider.notifier).show('That view is no longer available.');
      return;
    }
    // A filter the server marked invalid (it references a purged custom field)
    // fails inert by contract — never run it, say why instead.
    if (!view.isValid) {
      // Webapp `applyPreset`: the server's reason, else its fallback.
      ref.read(toastProvider.notifier).showError(
            view.invalidReason ?? 'This saved filter is invalid and cannot be applied.',
          );
      return;
    }
    // A chip is tappable without ever opening the drawer, so wait for the same
    // catalogs here: decoding maps stored server ids back to drawer options,
    // and half-loaded catalogs would resolve them to the wrong thing.
    await ref.read(leadFilterCatalogsProvider.future);
    if (!mounted) return;

    final values = ref
        .read(leadFilterCodecProvider)
        .decode(view.definition, ref.read(leadsFilterSpecProvider));
    ref.read(leadSavedFiltersProvider.notifier).apply(id);
    _applyFilters(values);
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  /// Whether a search, status chip or drawer filter is narrowing the list —
  /// the webapp then says "match your filters" instead of "yet".
  bool _isNarrowed() =>
      ref.read(leadSearchProvider).trim().isNotEmpty ||
      ref.read(leadFiltersProvider).activeCount > 0 ||
      ref.read(leadTabProvider).isNotEmpty;

  void _toggleTab(String id) =>
      ref.read(leadTabProvider.notifier).update((s) => toggleLeadTab(s, id));

  /// The webapp's Archived toggle: list, counts and search switch to archived
  /// leads (`is_archive=true`); the chip selection resets like a page change.
  void _toggleArchived() {
    ref.read(leadTabProvider.notifier).state = const {};
    ref.read(leadArchivedProvider.notifier).update((a) => !a);
  }

  /// The empty state's "Clear filters": search, chip and drawer back to all.
  void _resetListView() {
    _searchCtrl.clear();
    ref.read(leadSearchProvider.notifier).state = '';
    ref.read(leadTabProvider.notifier).state = const {};
    _clearFilters();
  }

  void _clearFilters() {
    ref.read(leadSavedFiltersProvider.notifier).deactivate();
    _applyFilters(FilterValues());
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
