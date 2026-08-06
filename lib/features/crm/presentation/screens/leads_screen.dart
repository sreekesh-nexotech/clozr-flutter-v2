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
import '../../application/providers/leads_providers.dart';
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
    final spec = ref.read(leadsFilterSpecProvider);
    final current = ref.read(leadFiltersProvider);
    final base = ref.read(leadBaseProvider);
    final activeView = ref.read(leadSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((l) => leadMatchesFilters(l, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: (name, draft) {
        ref.read(leadSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(leadFiltersProvider.notifier).state = result;
    // A manual Apply deactivates the active saved view unless the draft still
    // matches it exactly (prototype `deactivateViews` parity).
    final views = ref.read(leadSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(leadSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  // ── Saved-view row: My/All toggle + saved bookmark chips + Clear ──
  Widget _savedViewRow(bool teamAll, int filterCount) {
    final saved = ref.watch(leadSavedViewsProvider);
    return SizedBox(
      height: 34.h,
      child: Row(
        children: [
          _teamChip(teamAll),
          SizedBox(width: 8.w),
          Expanded(
            child: chips.SavedChipRow(
              views: [for (final v in saved.views) chips.SavedView(v.id, v.name)],
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

  void _toggleView(String id) {
    final saved = ref.read(leadSavedViewsProvider);
    if (saved.activeId == id) {
      // Tapping the active view deactivates it and clears the applied filters.
      ref.read(leadSavedViewsProvider.notifier).deactivate();
      ref.read(leadFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(leadSavedViewsProvider.notifier).apply(id);
    // Applying a view loads its values as the current (editable) filter state.
    ref.read(leadFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(leadSavedViewsProvider.notifier).clearActive();
    ref.read(leadFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }

  /// Switches the ownership scope. The list is refetched for the scope being
  /// entered rather than re-filtered locally — the row shape is scope-dependent,
  /// so a previously loaded list is never reused. The stale entry for the target
  /// scope is dropped first so the switch always hits the network.
  void _setTeamAll(bool teamAll) {
    ref.invalidate(leadsScopedProvider(!teamAll));
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
