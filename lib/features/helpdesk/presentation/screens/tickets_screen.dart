import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../data/api/status_keys.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/presentation/components/saved_chip_row.dart' as chips;
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/tickets_filter_spec.dart';
import '../../application/providers/tickets_providers.dart';
import '../../domain/entities/ticket.dart';
import '../components/ticket_card.dart';

/// Tickets list — brand header, title + search + filter, status tabs and the
/// My Tickets / Breaching soon chip row over a scrolling card list.
class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  final _searchCtrl = TextEditingController();

  /// The built-in vocabulary, used until `/crm/issue-statuses/` lands and in
  /// mock mode.
  static const _builtInTabs = ['all', 'new', 'open', 'pending', 'resolved', 'closed'];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(ticketSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Create ticket form here.
    registerAdd(
      ref,
      AddAction(label: 'New ticket', run: (ctx) => ctx.push(Routes.createTicket)),
    );

    // The list itself is the server-filtered fetch; `ticketsProvider` stays
    // the org-wide source the detail screen and the boards read.
    final ticketsAsync = ApiConfig.apiEnabled
        ? ref.watch(ticketsFilteredProvider)
        : ref.watch(ticketsProvider);
    final all = ticketsAsync.valueOrNull ?? const [];
    final serverCounts = ref.watch(ticketTabCountsProvider);
    // The org's own statuses drive the strip — names, order and ids, straight
    // from the catalog. The built-in five could not express "In Progress",
    // "Overdue" or "Duplicate", so those tickets had no tab of their own.
    final statusCatalog = ref.watch(ticketStatusOptionsProvider);
    final tabs = <(String, String)>[
      ('all', 'All'),
      if (statusCatalog.isEmpty)
        for (final k in _builtInTabs.skip(1)) (k, _label(k))
      else
        for (final s in statusCatalog) (s.id, s.name),
    ];
    final tab = ref.watch(ticketTabProvider);
    final searchOpen = ref.watch(ticketSearchOpenProvider);
    final query = ref.watch(ticketSearchProvider);
    final mine = ref.watch(ticketMineProvider);
    final breach = ref.watch(ticketBreachingProvider);
    final filterCount = ref.watch(ticketFiltersProvider).activeCount;

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Tickets',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () => ref.read(ticketSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search tickets…',
                onChanged: (v) => ref.read(ticketSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(ticketSearchProvider.notifier).state = '';
                  ref.read(ticketSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 12.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final (k, label) in tabs)
                    TabChip(
                      label:
                          '$label (${ticketTabCountOf(serverCounts, all, mine, breach, k)})',
                      active: _tabActive(tab, k, statusCatalog),
                      onTap: () => ref.read(ticketTabProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _savedViewRow(mine, breach, filterCount),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<Ticket>>(
            value: ticketsAsync,
            onRetry: () => ref.invalidate(ApiConfig.apiEnabled ? ticketsFilteredProvider : ticketsProvider),
            onRefresh: _refresh,
            data: (_) {
              final visible = ref.watch(filteredTicketsProvider);
              return visible.isEmpty
                  ? _empty()
                  : ListView.separated(
                      // So the gesture still works on a short list that fits
                      // the viewport without scrolling.
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => SizedBox(height: 12.h),
                      itemBuilder: (context, i) {
                        final t = visible[i];
                        return TicketCard(
                          ticket: t,
                          onTap: () => context.push('${Routes.ticketDetail}?id=${t.id}'),
                        );
                      },
                    );
            },
          ),
        ),
      ],
    );
  }

  String _label(String key) =>
      key == 'all' ? 'All' : StatusMeta$.ticket[key]?.label ?? key;

  /// Whether a chip reads as selected.
  ///
  /// Tolerant on purpose: another screen can set the tab to a folded key
  /// ("show me resolved") while the strip is keyed by the org's status ids, so
  /// the chip for the status that folds there should still light up.
  bool _tabActive(String tab, String chipKey, List<CatalogOption> catalog) {
    if (tab == chipKey) return true;
    for (final s in catalog) {
      if (s.id == chipKey && ticketStatusKey(s.name) == tab) return true;
    }
    return false;
  }

  /// Pull-to-refresh: the rows, the tab counts and the status catalog — a
  /// status an admin added since the screen mounted should appear too.
  Future<void> _refresh() async {
    refreshTickets(ref);
    ref.invalidate(ticketStatusCatalogProvider);
    if (ApiConfig.apiEnabled) {
      refreshTickets(ref);
      ref.invalidate(ticketStatusCountsProvider);
    }
    await settle([
      ref.read(ApiConfig.apiEnabled ? ticketsFilteredProvider.future : ticketsProvider.future),
      ref.read(ticketStatusCatalogProvider.future),
      if (ApiConfig.apiEnabled) ref.read(ticketStatusCountsProvider.future),
    ]);
  }

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    final spec = ref.read(ticketsFilterSpecProvider);
    final current = ref.read(ticketFiltersProvider);
    final base = ref.read(ticketBaseProvider);
    final dir = ref.read(ticketDirectoryProvider);
    final activeView = ref.read(ticketSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((t) => ticketMatchesFilters(t, draft, dir)).length,
      activeViewName: activeView?.name,
      existingViewNames: ref.read(ticketSavedViewsProvider).views.map((v) => v.name).toSet(),
      onSaveView: (name, draft) {
        ref.read(ticketSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(ticketFiltersProvider.notifier).state = result;
    // A manual Apply deactivates the active saved view unless the draft still
    // matches it exactly (prototype `deactivateViews` parity).
    final views = ref.read(ticketSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(ticketSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  // ── Saved-view row: My Tickets / Breaching quick chips (default views) +
  // saved bookmark chips + Clear. ──
  Widget _savedViewRow(bool mine, bool breach, int filterCount) {
    final saved = ref.watch(ticketSavedViewsProvider);
    return SizedBox(
      height: 34.h,
      child: Row(
        children: [
          _chip(
            label: 'My Tickets',
            icon: PhosphorIconsFill.userCircle,
            active: mine,
            filled: true,
            onTap: () => ref.read(ticketMineProvider.notifier).state = !mine,
          ),
          SizedBox(width: 8.w),
          _chip(
            label: 'Breaching soon',
            icon: PhosphorIconsFill.timer,
            active: breach,
            filled: false,
            iconColorOff: AppColors.warningDeep,
            onTap: () => ref.read(ticketBreachingProvider.notifier).state = !breach,
          ),
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
    final saved = ref.read(ticketSavedViewsProvider);
    if (saved.activeId == id) {
      // Tapping the active view deactivates it and clears the applied filters.
      ref.read(ticketSavedViewsProvider.notifier).deactivate();
      ref.read(ticketFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(ticketSavedViewsProvider.notifier).apply(id);
    // Applying a view loads its values as the current (editable) filter state.
    ref.read(ticketFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(ticketSavedViewsProvider.notifier).clearActive();
    ref.read(ticketFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool active,
    required bool filled,
    required VoidCallback onTap,
    Color? iconColorOff,
  }) {
    // Filled chip (My Tickets): navy when active. Outline chip (Breaching soon):
    // blue-subtle when active, white border when off.
    final Color bg;
    final Color fg;
    final Color iconColor;
    if (filled) {
      bg = active ? AppColors.navy : AppColors.white;
      fg = active ? AppColors.white : AppColors.textLabelAlt;
      iconColor = active ? AppColors.white : AppColors.textMuted2;
    } else {
      bg = active ? AppColors.blueSubtle : AppColors.white;
      fg = active ? AppColors.navy : AppColors.textLabelAlt;
      iconColor = active ? AppColors.blueBright : (iconColorOff ?? AppColors.textMuted2);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10.r),
          border: active ? null : Border.all(color: AppColors.borderCard),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.sp, color: iconColor),
            SizedBox(width: 6.w),
            Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return ListView(
      // Pullable even with nothing in it — an empty list is the state you most
      // want to retry from.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 56.h),
          child: Column(
            children: [
              Container(
                width: 66.r,
                height: 66.r,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.borderCardSoft, borderRadius: BorderRadius.circular(19.r)),
                child: Icon(PhosphorIconsRegular.ticket, size: 30.sp, color: AppColors.textPlaceholder),
              ),
              SizedBox(height: 16.h),
              Text('No tickets found', style: AppText.sectionTitle(), textAlign: TextAlign.center),
              SizedBox(height: 6.h),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 240.w),
                child: Text(
                  'Try a different status, or turn off the active filter to see all tickets.',
                  textAlign: TextAlign.center,
                  style: AppText.body(color: AppColors.textMuted).copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
