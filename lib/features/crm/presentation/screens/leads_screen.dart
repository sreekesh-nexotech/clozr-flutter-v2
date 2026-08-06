import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
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
    _searchCtrl.text = ref.read(leadSearchProvider);
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
      AddAction(label: 'Add lead', run: (ctx) => ctx.push(Routes.addLead)),
    );

    final async = ref.watch(leadsListProvider);
    final tab = ref.watch(leadTabProvider);
    final searchOpen = ref.watch(leadSearchOpenProvider);
    final query = ref.watch(leadSearchProvider);
    final teamAll = ref.watch(leadTeamAllProvider);
    final filterCount = ref.watch(leadFiltersProvider).activeCount;

    final tabBase = ref.watch(leadBaseProvider);
    // The org's own pipeline stages when `/crm/lead-statuses/` has loaded,
    // otherwise the built-in vocabulary. Name and dot colour both come from
    // the catalog, so the row looks unchanged but reads the org's stages.
    final tabDefs = ref.watch(leadTabsProvider);
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
              onSearch: () => ref.read(leadSearchOpenProvider.notifier).state = !searchOpen,
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
                  for (final t in tabDefs)
                    TabChip(
                      label: '${t.label} (${leadTabCount(tabBase, t.id)})',
                      active: tab == t.id,
                      dotColor: t.color,
                      onTap: () => ref.read(leadTabProvider.notifier).state = t.id,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _savedViewRow(teamAll, filterCount),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<Lead>>(
            value: async,
            onRetry: () => ref.invalidate(leadsScopedProvider),
            data: (_) {
              final visible = ref.watch(visibleLeadsProvider);
              if (visible.isEmpty) {
                return ListView(
                  children: [
                    EmptyState(
                      icon: PhosphorIconsRegular.magnifyingGlass,
                      title: 'No leads found',
                      body: 'Try a different status, clear filters, or add a new lead to get started.',
                      ctaLabel: 'Add lead',
                      ctaIcon: PhosphorIconsBold.plus,
                      onCta: () => context.push(Routes.addLead),
                    ),
                  ],
                );
              }
              return ListView.separated(
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
      onSaveView: _saveView,
    );
    if (result == null) return;

    ref.read(leadFiltersProvider.notifier).state = result;
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

  /// Persists the drawer draft as a saved filter. The API stores the backend's
  /// own param dict, so the draft is encoded before it is sent; server-side
  /// rejections (duplicate name, 5-per-module limit) come back as user-safe
  /// text and are shown as-is.
  Future<void> _saveView(String name, FilterValues draft) async {
    final definition = ref.read(leadFilterCodecProvider).encode(draft);
    final error = await ref.read(leadSavedFiltersProvider.notifier).save(name, definition);
    if (!mounted) return;
    ref.read(toastProvider.notifier).show(error ?? 'View "$name" saved');
  }

  // ── Saved-view row: My/All toggle + saved bookmark chips + Clear ──
  Widget _savedViewRow(bool teamAll, int filterCount) {
    final saved = ref.watch(leadSavedFiltersProvider);
    return SizedBox(
      height: 34.h,
      child: Row(
        children: [
          _teamChip(teamAll),
          SizedBox(width: 8.w),
          Expanded(
            child: chips.SavedChipRow(
              views: [for (final f in saved.filters) chips.SavedView(f.id, f.name)],
              active: {if (saved.activeId != null) saved.activeId!},
              showClearAlways: filterCount > 0,
              onToggle: _toggleView,
              onClear: _clearFilters,
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
      ref.read(leadFiltersProvider.notifier).state = FilterValues();
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
    // catalogs here: decoding maps stored server ids back to drawer options,
    // and half-loaded catalogs would resolve them to the wrong thing.
    await ref.read(leadFilterCatalogsProvider.future);
    if (!mounted) return;

    final values = ref
        .read(leadFilterCodecProvider)
        .decode(view.definition, ref.read(leadsFilterSpecProvider));
    ref.read(leadSavedFiltersProvider.notifier).apply(id);
    ref.read(leadFiltersProvider.notifier).state = values;
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(leadSavedFiltersProvider.notifier).deactivate();
    ref.read(leadFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }

  /// Switches the ownership scope. The list is refetched for the scope being
  /// entered rather than re-filtered locally — the row shape is scope-dependent,
  /// so a previously loaded list is never reused. The stale entry for the target
  /// scope is dropped first so the switch always hits the network.
  void _setTeamAll(bool teamAll) {
    ref.invalidate(leadsScopedProvider(LeadListQuery(
      mineOnly: !teamAll,
      filters: ref.read(leadFilterParamsProvider),
    )));
    ref.read(leadTeamAllProvider.notifier).state = teamAll;
  }

  Widget _teamChip(bool teamAll) {
    final active = !teamAll;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setTeamAll(!teamAll),
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: active ? AppColors.blueSubtle : AppColors.bgChipGrey,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsFill.bookmarkSimple,
                size: 13.sp, color: active ? AppColors.blueBright : AppColors.textLabelAlt),
            SizedBox(width: 5.w),
            Text(teamAll ? 'All leads' : 'My leads',
                style: AppText.custom(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: active ? AppColors.blueBright : AppColors.textLabelAlt)),
          ],
        ),
      ),
    );
  }
}
