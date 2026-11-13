import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/status_groups/status_groups.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/status_group_bar.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../auth/application/providers/module_perm_providers.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../crm/application/providers/saved_filters_providers.dart';
import '../../../crm/presentation/components/saved_chip_row.dart' as chips;
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/tickets_filter_spec.dart';
import '../../application/providers/tickets_providers.dart';
import '../../domain/entities/ticket.dart';
import '../components/ticket_card.dart';
import '../../../onboarding/presentation/tour_anchor.dart';

/// Tickets list — the webapp's `TicketsListScreen` on a phone: search, the
/// org's status chips (multi-select), the My Tickets / All presets, saved
/// views on `/crm/saved-filters/`, the 7-facet drawer and row actions.
class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  final _searchCtrl = TextEditingController();

  /// The built-in vocabulary, used until `/crm/issue-statuses/` lands and in
  /// mock mode.
  static const _builtInTabs = ['new', 'open', 'pending', 'resolved', 'closed'];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(ticketSearchProvider);
    // The dashboard's "SLA Breaches" KPI links here with `?breaching=1` so
    // the list opens on the Breaching-soon view rather than every ticket.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final q = GoRouterState.of(context).uri.queryParameters;
      // The dashboard's org-wide figures (Open tickets, SLA Breaches, …) link
      // here with `all=1`: the list must open on every ticket, not on "My
      // Tickets", or a figure of 29 lands on an empty list.
      if (q['all'] == '1') {
        ref.read(ticketMineProvider.notifier).state = false;
      }
      final b = q['breaching'];
      if (b == '1' || b == 'true') {
        ref.read(ticketBreachingProvider.notifier).state = true;
      }
      // The dashboard's donut slices, category bars and roster rows link to
      // one facet each: SLA bucket, priority, category (issue type id) or
      // assignee (user id). Applied as the drawer would, on top of nothing.
      final sla = q['sla'];
      final pri = q['pri'];
      final cat = q['cat'];
      final assignee = q['assignee'];
      if ((sla ?? pri ?? cat ?? assignee) != null) {
        final values = FilterValues();
        if (sla != null && sla.isNotEmpty) {
          values['sla'] = RadioValue(id: sla, defaultId: 'any');
        }
        if (pri != null && pri.isNotEmpty) {
          values['pri'] = ChoiceValue(ids: {pri});
        }
        if (cat != null && cat.isNotEmpty) {
          values['cats'] = ChoiceValue(ids: {cat});
        }
        if (assignee != null && assignee.isNotEmpty) {
          values['assignees'] = ChoiceValue(ids: {assignee});
        }
        ref.read(ticketFiltersProvider.notifier).state = values;
        ref.read(ticketSavedFiltersProvider.notifier).deactivate();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _canEdit => ref.read(helpdeskEditableProvider);

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(modulePermProvider('issue'));
    // Contextual add: the bottom-nav `+` opens the Create ticket form here.
    registerAdd(
      ref,
      AddAction(
          label: 'New ticket',
          module: 'issue',
          run: (ctx) => ctx.push(Routes.createTicket)),
    );

    final ticketsAsync = ApiConfig.apiEnabled
        ? ref.watch(ticketsFilteredProvider)
        : ref.watch(ticketsProvider);
    final all = ticketsAsync.valueOrNull ?? const [];
    final serverCounts = ref.watch(ticketTabCountsProvider);
    final statusCatalog = ref.watch(ticketStatusOptionsProvider);
    final statusChips = ref.watch(ticketStatusChipsProvider);
    final tabs = <(String, String, Color?)>[
      if (statusCatalog.isEmpty)
        for (final k in _builtInTabs) (k, _label(k), null)
      else
        for (final s in statusCatalog) (s.id, s.name, s.color),
    ];
    final searchOpen = ref.watch(ticketSearchOpenProvider);
    final query = ref.watch(ticketSearchProvider);
    final mine = ref.watch(ticketMineProvider);
    final breach = ref.watch(ticketBreachingProvider);
    // A dashboard card's "open only" scope counts as a filter (badge + Clear).
    final filterCount = ref.watch(ticketFiltersProvider).activeCount +
        (ref.watch(ticketOpenOnlyProvider) ? 1 : 0) +
        (ref.watch(ticketScopeParamsProvider).isNotEmpty ? 1 : 0);
    final saved = ref.watch(ticketSavedFiltersProvider);
    // Webapp `hasNarrowingFilters`: anything the user picked beyond the
    // default "My Tickets" scope — it drives "Clear filters" and the empty
    // state's wording.
    final narrowing = filterCount > 0 ||
        query.trim().isNotEmpty ||
        statusChips.isNotEmpty ||
        ref.watch(ticketGroupProvider) != null ||
        saved.activeId != null ||
        breach;

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              tourArea: 'tickets',
              title: 'Tickets',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () => ref
                  .read(ticketSearchOpenProvider.notifier)
                  .state = !searchOpen,
              onFilter: _openFilters,
              // Tickets › Trash (C09): deleted tickets, restorable.
              trailing: hasPermission(ref, 'issue', PermVerb.delete)
                  ? IconButton(
                      tooltip: 'Trash',
                      icon: Icon(PhosphorIconsRegular.trash,
                          size: 20.sp, color: AppColors.textSecondary),
                      onPressed: () => context.push(Routes.ticketTrash),
                    )
                  : null,
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search tickets, reference or customer…',
                onChanged: (v) =>
                    ref.read(ticketSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(ticketSearchProvider.notifier).state = '';
                  ref.read(ticketSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 12.h),
            // The org's statuses grouped open / on hold / resolved (Oct 2026
            // header); the flat per-status row only while the catalog is
            // unavailable.
            if (statusCatalog.isNotEmpty)
              _groupBar(statusCatalog, statusChips,
                  counts: (k) =>
                      ticketTabCountOf(serverCounts, all, mine, breach, k))
            else
              SizedBox(
                height: 40.h,
                child: TabChipRow(
                  children: [
                    TabChip(
                      label:
                          'All (${ticketTabCountOf(serverCounts, all, mine, breach, 'all')})',
                      active: statusChips.isEmpty,
                      onTap: () => _toggleStatus('all'),
                    ),
                    for (final (k, label, color) in tabs)
                      TabChip(
                        label:
                            '$label (${ticketTabCountOf(serverCounts, all, mine, breach, k)})',
                        active: _chipActive(statusChips, k, statusCatalog),
                        dotColor: color,
                        onTap: () => _toggleStatus(k),
                      ),
                  ],
                ),
              ),
            SizedBox(height: 12.h),
            _presetRow(mine, breach),
            // Says which scope the status counts above are for, so a count
            // changing with the chip is never a surprise (UI/UX audit #22).
            Padding(
              padding: EdgeInsets.only(top: 8.h, left: 2.w),
              child: Text(
                mine
                    ? 'Showing tickets assigned to you — counts are for My Tickets'
                    : 'Showing all tickets — counts are for the whole queue',
                style: AppText.caption(),
              ),
            ),
            if (saved.filters.isNotEmpty || narrowing) ...[
              SizedBox(height: 10.h),
              chips.SavedChipRow(
                views: [
                  for (final f in saved.filters) chips.SavedView(f.id, f.name)
                ],
                active: {if (saved.activeId != null) saved.activeId!},
                showClearAlways: narrowing,
                onToggle: _toggleView,
                onClear: _clearAll,
                // Webapp `SavedViewChips`: × deletes the view after a confirm.
                onRemove: _removeView,
                webappStyle: true,
              ),
            ],
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: TourAnchor(
              id: TourAnchors.ticketsList,
              child: AsyncStateView<List<Ticket>>(
                value: ticketsAsync,
                onRetry: _refresh,
                onRefresh: _refresh,
                error: (e, retry) => AppRefresh(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      ErrorState.forSubject(e, 'your tickets', onRetry: retry)
                    ],
                  ),
                ),
                data: (_) {
                  final visible = ref.watch(filteredTicketsProvider);
                  return visible.isEmpty
                      ? _empty(
                          narrowing: narrowing,
                          mine: mine,
                          canCreate: perm.create)
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => SizedBox(height: 12.h),
                          itemBuilder: (context, i) {
                            final t = visible[i];
                            return TicketCard(
                              ticket: t,
                              onTap: () => context
                                  .push('${Routes.ticketDetail}?id=${t.id}'),
                              onLongPress: () => _rowActions(t),
                            );
                          },
                        );
                },
              )),
        ),
      ],
    );
  }

  String _label(String key) => StatusMeta$.ticket[key]?.label ?? key;

  /// Whether a chip reads as selected — by id, or through a folded key another
  /// screen put in the set ("show me resolved").
  bool _chipActive(
      Set<String> picked, String chipKey, List<CatalogOption> catalog) {
    if (picked.contains(chipKey)) return true;
    for (final s in catalog) {
      if (s.id == chipKey && picked.contains(ticketStatusKey(s.name)))
        return true;
    }
    return false;
  }

  /// The group row: `All`, then Open / On hold / Resolved; a picked group
  /// opens a second row with its own statuses, which narrow it further.
  Widget _groupBar(List<CatalogOption> statuses, Set<String> picked,
      {required int Function(String) counts}) {
    // A folded key another screen put in the set ("resolved") names no status,
    // so the group the screen set alongside it stays the open one.
    final open = StatusGroups.displayedGroup(
      picked: picked,
      group: ref.watch(ticketGroupProvider),
      statuses: statuses,
      groupOf: StatusGroups.ofTicket,
      keyOf: (s) => s.id,
    );
    final server = ref.watch(ticketTabCountsProvider);
    int groupCount(String code) =>
        server[StatusGroups.countKey(code)] ??
        [
          for (final s in statuses)
            if (StatusGroups.ofTicket(s) == code) counts(s.id)
        ].fold(0, (a, b) => a + b);
    return StatusGroupBar(
      allCount: counts('all'),
      allActive: picked.isEmpty && open == null,
      onAll: () => _toggleStatus('all'),
      groups: [
        for (final g in StatusGroups.ticket)
          StatusGroupChip(
              code: g.code, label: g.label, count: groupCount(g.code)),
      ],
      activeGroup: open,
      onGroup: (code) {
        // A group the org has no status in cannot be listed.
        if (!statuses.any((s) => StatusGroups.ofTicket(s) == code)) return;
        _toggleStatus('all');
        ref.read(ticketGroupProvider.notifier).state =
            code == open ? null : code;
      },
      statuses: [
        for (final s in statuses)
          if (open != null && StatusGroups.ofTicket(s) == open)
            StatusGroupStatusChip(
              key: s.id,
              label: s.name,
              count: counts(s.id),
              active: _chipActive(picked, s.id, statuses),
              color: s.color,
            ),
      ],
      onStatus: (id) {
        _toggleStatus(id);
        ref.read(ticketGroupProvider.notifier).state = open;
      },
    );
  }

  // ── Header controls ──

  /// Webapp `toggleStatus`: a status toggles in / out of the set (OR); "All"
  /// clears it. Drops an applied saved view.
  void _toggleStatus(String key) {
    ref.read(ticketSavedFiltersProvider.notifier).deactivate();
    final n = ref.read(ticketStatusChipsProvider.notifier);
    if (key == 'all') {
      n.state = const <String>{};
      ref.read(ticketGroupProvider.notifier).state = null;
      return;
    }
    final next = {...n.state};
    // A folded key from another screen is swapped for the real id it covers.
    final catalog = ref.read(ticketStatusOptionsProvider);
    next.removeWhere(
        (k) => catalog.any((s) => s.id == key && ticketStatusKey(s.name) == k));
    next.contains(key) ? next.remove(key) : next.add(key);
    n.state = next;
  }

  /// The webapp's two presets — "My Tickets" (the default) and "All" — plus
  /// the app's own "Breaching soon".
  Widget _presetRow(bool mine, bool breach) {
    return SizedBox(
      height: 34.h,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            label: 'My Tickets',
            icon: PhosphorIconsFill.userCircle,
            active: mine,
            filled: true,
            onTap: () => _setPreset(true),
          ),
          SizedBox(width: 8.w),
          _chip(
            // "All tickets", not "All": the status tab row already has an
            // "All (n)" (UI/UX audit #22).
            label: 'All tickets',
            icon: PhosphorIconsFill.bookmarkSimple,
            active: !mine,
            filled: true,
            onTap: () => _setPreset(false),
          ),
          SizedBox(width: 8.w),
          _chip(
            label: 'Breaching soon',
            icon: PhosphorIconsFill.timer,
            active: breach,
            filled: false,
            iconColorOff: AppColors.warningDeep,
            onTap: () =>
                ref.read(ticketBreachingProvider.notifier).state = !breach,
          ),
        ],
      ),
    );
  }

  void _setPreset(bool mine) {
    ref.read(ticketSavedFiltersProvider.notifier).deactivate();
    ref.read(ticketMineProvider.notifier).state = mine;
  }

  /// Pull-to-refresh: the rows, the chip counts, the status catalog and the
  /// saved views.
  Future<void> _refresh() async {
    refreshTickets(ref);
    ref.invalidate(ticketStatusCatalogProvider);
    if (ApiConfig.apiEnabled) ref.invalidate(ticketStatusCountsProvider);
    await settle([
      ref.read(ApiConfig.apiEnabled
          ? ticketsFilteredProvider.future
          : ticketsProvider.future),
      ref.read(ticketStatusCatalogProvider.future),
      if (ApiConfig.apiEnabled) ref.read(ticketStatusCountsProvider.future),
      ref.read(ticketSavedFiltersProvider.notifier).load(),
    ]);
  }

  // ── Filter drawer + saved views ──

  Future<void> _openFilters() async {
    // The sheet keeps the spec it opens with, so the org catalogs behind the
    // options must have landed first.
    await ref.read(ticketFilterCatalogsProvider.future);
    if (!mounted) return;
    final spec = ref.read(ticketsFilterSpecProvider);
    final current = ref.read(ticketFiltersProvider);
    final base = ref.read(ticketBaseProvider);
    final dir = ref.read(ticketDirectoryProvider);
    final saved = ref.read(ticketSavedFiltersProvider);

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      // Facets run server-side in API mode and [base] is already narrowed by
      // the applied ones, so no device-side guess at the count (webapp:
      // "Apply filters").
      previewCount: ApiConfig.apiEnabled
          ? (_) => -1
          : (draft) =>
              base.where((t) => ticketMatchesFilters(t, draft, dir)).length,
      activeViewName: saved.active?.name,
      existingViewNames: saved.filters.map((f) => f.name).toSet(),
      onSaveView: _saveView,
    );
    if (result == null) return;

    ref.read(ticketFiltersProvider.notifier).state = result;
    // Hand-picked facets replace an applied saved view, unless the draft still
    // means exactly what the view stores.
    final active = ref.read(ticketSavedFiltersProvider).active;
    if (active != null &&
        !sameFilterDefinition(
            encodeTicketView(result).definition, active.definition)) {
      ref.read(ticketSavedFiltersProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  /// Webapp `saveView` / `updateView`: POST (or PATCH the applied view)
  /// `/crm/saved-filters/` with module `issue` and the `<field>__in` /
  /// `<field>__not` definition.
  Future<void> _saveView(String name, FilterValues draft) async {
    final toast = ref.read(toastProvider.notifier);
    final built = encodeTicketView(draft);
    if (built.definition.isEmpty) {
      toast.showError('Add at least one filter before saving.');
      return;
    }
    if (built.unsupported.isNotEmpty) {
      toast.show(
          '"Is not" isn\'t supported for ${built.unsupported.join(', ')} — those were left out.');
    }
    final updating = ref
        .read(ticketSavedFiltersProvider)
        .filters
        .any((f) => f.name.toLowerCase() == name.trim().toLowerCase());
    final error = await ref
        .read(ticketSavedFiltersProvider.notifier)
        .save(name, built.definition);
    if (!mounted) return;
    if (error != null) {
      toast.showError(error);
      return;
    }
    // The saved view is now the applied one: the server resolves the list
    // from `saved_filter_id`, so the presets and chips step aside (webapp).
    ref.read(ticketFiltersProvider.notifier).state = draft.copy();
    ref.read(ticketMineProvider.notifier).state = false;
    ref.read(ticketStatusChipsProvider.notifier).state = const <String>{};
    ref.read(ticketGroupProvider.notifier).state = null;
    toast.show(updating ? 'View updated' : 'View saved');
  }

  /// Webapp `applyPreset`: the view's definition fills the drawer, the preset
  /// switches to "All", the chips clear, and the server resolves the rows
  /// from `saved_filter_id`. Tapping the applied view again turns it off.
  void _toggleView(String id) {
    final saved = ref.read(ticketSavedFiltersProvider);
    if (saved.activeId == id) {
      ref.read(ticketSavedFiltersProvider.notifier).deactivate();
      ref.read(ticketFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.filters.where((f) => f.id == id).firstOrNull;
    if (view == null) {
      ref
          .read(toastProvider.notifier)
          .show('That view is no longer available.');
      return;
    }
    // An invalid view fails inert (webapp: greyed with a warning).
    if (!view.isValid) {
      ref.read(toastProvider.notifier).showError(
          'View "${view.name}" refers to a field that no longer exists.');
      return;
    }
    ref.read(ticketFiltersProvider.notifier).state =
        decodeTicketView(view.definition);
    ref.read(ticketMineProvider.notifier).state = false;
    ref.read(ticketStatusChipsProvider.notifier).state = const <String>{};
    ref.read(ticketGroupProvider.notifier).state = null;
    ref.read(ticketSavedFiltersProvider.notifier).apply(id);
  }

  /// `DELETE /crm/saved-filters/{id}/` after the chip's "Delete “<name>”?"
  /// confirm; an applied view falls back to no view.
  Future<void> _removeView(String id) async {
    final wasActive = ref.read(ticketSavedFiltersProvider).activeId == id;
    final error =
        await ref.read(ticketSavedFiltersProvider.notifier).remove(id);
    if (!mounted) return;
    if (error != null) {
      ref.read(toastProvider.notifier).showError(error);
      return;
    }
    if (wasActive)
      ref.read(ticketFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('View deleted');
  }

  /// Webapp `clearAll`: facets, search, status chips and saved view cleared,
  /// and the preset switched to "All".
  void _clearAll() {
    _searchCtrl.clear();
    ref.read(ticketSearchProvider.notifier).state = '';
    ref.read(ticketSearchOpenProvider.notifier).state = false;
    ref.read(ticketFiltersProvider.notifier).state = FilterValues();
    ref.read(ticketStatusChipsProvider.notifier).state = const <String>{};
    ref.read(ticketGroupProvider.notifier).state = null;
    ref.read(ticketBreachingProvider.notifier).state = false;
    ref.read(ticketOpenOnlyProvider.notifier).state = false;
    ref.read(ticketScopeParamsProvider.notifier).state = const {};
    ref.read(ticketMineProvider.notifier).state = false;
    ref.read(ticketSavedFiltersProvider.notifier).deactivate();
  }

  // ── Row actions ──

  /// The webapp row's ACTIONS: View, Edit (disabled with the permission copy
  /// without `issue` update).
  void _rowActions(Ticket t) {
    final canEdit = _canEdit;
    showActionMenu(
      context,
      title: t.displayRef,
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.eye,
          label: 'View ticket',
          onTap: () => context.push('${Routes.ticketDetail}?id=${t.id}'),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit ticket',
          enabled: canEdit,
          sublabel: canEdit ? null : PermissionCopy.update,
          onTap: () => context.push('${Routes.editTicket}?id=${t.id}'),
        ),
      ],
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool active,
    required bool filled,
    required VoidCallback onTap,
    Color? iconColorOff,
  }) {
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
      iconColor = active
          ? AppColors.blueBright
          : (iconColorOff ?? AppColors.textMuted2);
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
            Text(label,
                style: AppText.custom(
                    size: 12.5, weight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }

  /// The webapp's three empty states: filters that match nothing (→ Clear
  /// filters), nothing assigned under "My Tickets" (→ New Ticket), and an org
  /// with no tickets yet (→ New Ticket). New Ticket is hidden without create.
  Widget _empty(
      {required bool narrowing, required bool mine, required bool canCreate}) {
    final (IconData icon, String title, String body) = narrowing
        ? (
            PhosphorIconsRegular.magnifyingGlassMinus,
            'No tickets match your filters',
            'Try widening your search or clearing a filter to see more.',
          )
        : mine
            ? (
                PhosphorIconsRegular.ticket,
                'No tickets assigned to you',
                'Nothing is assigned to you right now. Raise a ticket, or switch to “All tickets” to see the whole team’s queue.',
              )
            : (
                PhosphorIconsRegular.ticket,
                'No tickets yet',
                'Tickets track the issues your customers raise. Create your first one to get started.',
              );
    final showAction = narrowing || canCreate;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 48.h),
          child: Column(
            children: [
              Container(
                width: 66.r,
                height: 66.r,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.borderCardSoft,
                    borderRadius: BorderRadius.circular(19.r)),
                child:
                    Icon(icon, size: 30.sp, color: AppColors.textPlaceholder),
              ),
              SizedBox(height: 16.h),
              Text(title,
                  style: AppText.sectionTitle(), textAlign: TextAlign.center),
              SizedBox(height: 6.h),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 260.w),
                child: Text(body,
                    textAlign: TextAlign.center,
                    style: AppText.body(color: AppColors.textMuted)
                        .copyWith(height: 1.5)),
              ),
              if (showAction) ...[
                SizedBox(height: 18.h),
                GestureDetector(
                  onTap: narrowing
                      ? _clearAll
                      : () => context.push(Routes.createTicket),
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 18.w, vertical: 11.h),
                    decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(11.r)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          narrowing
                              ? PhosphorIconsBold.x
                              : PhosphorIconsBold.plus,
                          size: 15.sp,
                          color: AppColors.white),
                      SizedBox(width: 7.w),
                      Text(narrowing ? 'Clear filters' : 'New Ticket',
                          style: AppText.custom(
                              size: 14,
                              weight: FontWeight.w700,
                              color: AppColors.white)),
                    ]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
