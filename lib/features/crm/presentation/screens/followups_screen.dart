import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/widgets/row_actions_sheet.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/status_groups/status_groups.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/status_group_bar.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/customer_call.dart';
import '../../application/filters/followups_filter_spec.dart';
import '../../application/providers/crm_module_schema_providers.dart'
    show customerRowProvider;
import '../../application/filters/tasks_filter_spec.dart'
    show taskSavedFiltersProvider;
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_tasks_providers.dart'
    show toggleCrmTaskChip, crmTaskOtherChip;
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../application/providers/saved_filters_providers.dart'
    show sameFilterDefinition;
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/followup.dart';
import '../components/followup_card.dart';
import '../components/saved_chip_row.dart' as chips;
import '../sheets/add_followup_sheet.dart';
import 'due_date_approvals_screen.dart'
    show pendingDueDateCountProvider, approvalCountsProvider;

/// Follow-ups list — checkbox cards grouped overdue→upcoming→done, wired to the
/// webapp's task drawer, server-side saved views and the contextual Add
/// follow-up sheet.
class FollowupsScreen extends ConsumerStatefulWidget {
  const FollowupsScreen({super.key});

  @override
  ConsumerState<FollowupsScreen> createState() => _FollowupsScreenState();
}

class _FollowupsScreenState extends ConsumerState<FollowupsScreen> {
  /// Long press: the shared row actions (UI/UX audit #52) — View / Edit.
  Future<void> _rowMenu(String id, String title) async {
    final pick = await showRowActionsSheet(context, title: title, actions: [
      RowAction.view('follow-up'),
      RowAction.edit('follow-up'),
    ]);
    if (pick == null || !mounted) return;
    if (pick == 'view') {
      context.push('${Routes.followupDetail}?id=$id');
      return;
    }
    if (!ensurePermission(ref, 'followup', PermVerb.update)) return;
    context.push('${Routes.editFollowup}?id=$id');
  }

  final _searchCtrl = TextEditingController();

  /// Non-status views reachable by deep link (the CRM home "Followups missed"
  /// card). Shown, selected, while active so the narrowed list says why.
  static const _deepLinkTabs = <String, String>{'overdue': 'Overdue'};

  /// The lanes shown in API mode while `crm-task-statuses` is in flight — the
  /// four the backend seeds on every org, keyed by lane name like the real ones.
  static const _seededLaneTabs = <(String, String, Color)>[
    ('Open', 'Open', Color(0xFF3B82F6)),
    ('In Progress', 'In Progress', Color(0xFFF59E0B)),
    ('Completed', 'Completed', Color(0xFF10B981)),
    ('Cancelled', 'Cancelled', Color(0xFF6B7280)),
  ];

  /// Mock mode: rows carry only the built-in buckets.
  static final _mockLaneTabs = <(String, String, Color)>[
    for (final k in const ['overdue', 'due', 'done'])
      (k, StatusMeta$.followup[k]!.label, StatusMeta$.followup[k]!.color),
  ];

  @override
  void initState() {
    super.initState();
    // Coming back to Follow-ups: the rows, card layout and lanes were loaded on
    // an earlier visit and would otherwise be shown as they were then.
    // Re-fetch them, keeping the current cards on screen until the fresh ones
    // arrive. Skipped on the first visit, whose fetches are already in flight.
    if (ref.read(followupsProvider).hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        refreshFollowups(ref);
        ref.invalidate(followupCardSchemaFutureProvider);
        ref.invalidate(taskStatusCatalogProvider);
      });
    }
    // A query left behind by a collapsed box would filter the list with
    // nothing on screen saying so; only keep it while the box is open.
    if (!ref.read(followupSearchOpenProvider) &&
        ref.read(followupSearchProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(followupSearchProvider.notifier).state = '';
      });
    } else {
      _searchCtrl.text = ref.read(followupSearchProvider);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Add follow-up sheet here.
    registerAdd(
      ref,
      AddAction(label: 'Add follow-up', module: 'followup', run: _openAddSheet),
    );

    // Counts come from the server-filtered rows (search, drawer, saved view)
    // and ignore the chip selection — the webapp's board counts.
    final all = ApiConfig.apiEnabled
        ? ref.watch(followupsBaseProvider)
        : ref.watch(followupsAllProvider);
    final async = ApiConfig.apiEnabled
        ? ref.watch(followupsQueriedProvider)
        : ref.watch(followupsProvider);
    final tab = ref.watch(followupTabProvider);
    final selected = ref.watch(followupChipsProvider);
    final searchOpen = ref.watch(followupSearchOpenProvider);
    final query = ref.watch(followupSearchProvider);
    final filterCount = ref.watch(followupFiltersProvider).activeCount;
    // Watched to start the drawer's catalogs at mount; without this the drawer
    // would snapshot them unloaded and drop sections.
    ref.watch(followupTypeOptionsProvider);
    ref.watch(taskPriorityOptionsProvider);
    ref.watch(assignableUsersForModuleProvider('followup'));
    ref.watch(assignableTeamsForModuleProvider('followup'));
    final statuses = ref.watch(taskStatusOptionsProvider);
    final schema = ref.watch(followupCardSchemaProvider);
    // Starts the Add-sheet's layout + picker catalogs now, so the first tap on
    // `+` opens the org's form rather than the built-in one.
    ref.watch(followupFormReadyProvider);

    // The server's aggregate when it answered, else the loaded rows. The
    // server has no Overdue aggregate, so that view always counts locally.
    final counts = ref.watch(followupStatusCountsProvider).valueOrNull ??
        const <String, int>{};
    int countOf(String k) =>
        (k == 'overdue' ? null : counts[k.toLowerCase().trim()]) ??
        followupTabCount(all, k);
    final otherCount = counts[crmTaskOtherChip] ??
        all.where((f) => followupInNoLane(f, statuses)).length;
    final tabs = <(String, String, Color?)>[
      ('all', 'All', null),
      if (_deepLinkTabs.containsKey(tab)) (tab, _deepLinkTabs[tab]!, null),
      if (statuses.isNotEmpty)
        for (final s in statuses) (s.name, s.name, crmTaskStatusColor(s))
      else if (ApiConfig.apiEnabled)
        ..._seededLaneTabs
      else
        ..._mockLaneTabs,
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
              title: 'Follow-ups',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () {
                // Collapsing the box drops the query, like clearing the webapp's
                // search box — a hidden query would keep narrowing the list.
                if (searchOpen) {
                  _searchCtrl.clear();
                  ref.read(followupSearchProvider.notifier).state = '';
                }
                ref.read(followupSearchOpenProvider.notifier).state =
                    !searchOpen;
              },
              onFilter: _openFilters,
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search follow-ups…',
                onChanged: (v) =>
                    ref.read(followupSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(followupSearchProvider.notifier).state = '';
                  ref.read(followupSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 10.h),
            // The org's lanes grouped by type (Oct 2026 header); the flat
            // per-lane row only while `crm-task-statuses` is unavailable.
            if (statuses.isNotEmpty)
              _groupBar(statuses, tab, selected,
                  countOf: countOf, otherCount: otherCount)
            else
              SizedBox(
                height: 40.h,
                child: TabChipRow(
                  children: [
                    for (final (k, lbl, dot) in tabs)
                      TabChip(
                        label: '$lbl (${countOf(k)})',
                        dotColor: dot,
                        active: k == 'all'
                            ? tab == 'all' && selected.isEmpty
                            : _deepLinkTabs.containsKey(k)
                                ? tab == k
                                : selected.contains(k),
                        onTap: () => _tapChip(k),
                      ),
                    // Webapp "Other / no status": only when some follow-up sits in
                    // no lane, or it is selected.
                    if (otherCount > 0 || selected.contains(crmTaskOtherChip))
                      TabChip(
                        label: 'Other / no status ($otherCount)',
                        active: selected.contains(crmTaskOtherChip),
                        onTap: () => _tapChip(crmTaskOtherChip),
                      ),
                  ],
                ),
              ),
            _approvalsLink(),
            SizedBox(height: 12.h),
            _savedViewRow(filterCount),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<Followup>>(
            value: async,
            onRetry: () => refreshFollowups(ref),
            onRefresh: _refresh,
            data: (_) {
              final visible = ref.watch(visibleFollowupsProvider);
              if (visible.isEmpty) {
                return ListView(
                  // So the gesture still works with nothing to scroll.
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _isNarrowed()
                        ? EmptyState(
                            icon: PhosphorIconsRegular.funnel,
                            title: 'No follow-ups match your filters',
                            body:
                                'Try widening your search or clearing a filter to see more.',
                            ctaLabel: 'Clear filters',
                            ctaIcon: PhosphorIconsBold.xCircle,
                            onCta: _resetListView,
                          )
                        : EmptyState(
                            icon: PhosphorIconsRegular.checkCircle,
                            title: 'No follow-ups yet',
                            body:
                                'Follow-ups keep your next touchpoint with a lead or customer on schedule. Add your first one to get started.',
                            ctaLabel: 'Add follow-up',
                            ctaIcon: PhosphorIconsBold.plus,
                            onCta: () => _openAddSheet(context),
                          ),
                  ],
                );
              }
              return ListView.separated(
                // Scrolling the results puts the search keyboard away. Without
                // it the only exit is the search field's own × chip, so the
                // keyboard covered the rows the user had just searched for.
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                itemCount: visible.length,
                separatorBuilder: (_, __) => SizedBox(height: 12.h),
                itemBuilder: (context, i) {
                  final f = visible[i];
                  return FollowupCard(
                    followup: f,
                    // Resolved here rather than in the card so the pill and the
                    // chip above it always agree on name and colour.
                    status: followupStatusMeta(f, statuses),
                    schema: schema,
                    onTap: () =>
                        context.push('${Routes.followupDetail}?id=${f.id}'),
                    onLongPress: () => _rowMenu(f.id, f.title),
                    onCall: () => _callRelated(f),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// The group row: `All`, the four status types and "Other / no status"; a
  /// picked type opens a second row with its own lanes. The deep-linked
  /// "Overdue" view leads the row while it is the one applied.
  Widget _groupBar(
    List<CatalogOption> statuses,
    String tab,
    Set<String> selected, {
    required int Function(String) countOf,
    required int otherCount,
  }) {
    final open = tab != 'all'
        ? null
        : StatusGroups.displayedGroup(
            picked: selected,
            group: ref.watch(followupGroupProvider),
            statuses: statuses,
            groupOf: StatusGroups.ofTyped,
            keyOf: (s) => s.name,
          );
    final server = ref.watch(followupStatusCountsProvider).valueOrNull ??
        const <String, int>{};
    int groupCount(String code) =>
        server[StatusGroups.countKey(code)] ??
        [
          for (final s in statuses)
            if (StatusGroups.ofTyped(s) == code) countOf(s.name)
        ].fold(0, (a, b) => a + b);
    return StatusGroupBar(
      leading: [
        if (_deepLinkTabs.containsKey(tab))
          TabChip(
              label: '${_deepLinkTabs[tab]} (${countOf(tab)})',
              active: true,
              onTap: () => _tapChip(tab)),
      ],
      allCount: countOf('all'),
      allActive: tab == 'all' && selected.isEmpty && open == null,
      onAll: () => _tapChip('all'),
      groups: [
        for (final g in StatusGroups.task)
          StatusGroupChip(
              code: g.code, label: g.label, count: groupCount(g.code)),
      ],
      activeGroup: open,
      onGroup: (code) {
        ref.read(followupTabProvider.notifier).state = 'all';
        ref.read(followupChipsProvider.notifier).state = const {};
        ref.read(followupGroupProvider.notifier).state =
            code == open ? null : code;
      },
      statuses: [
        for (final s in statuses)
          if (open != null && StatusGroups.ofTyped(s) == open)
            StatusGroupStatusChip(
              key: s.name,
              label: s.name,
              count: countOf(s.name),
              active: selected.contains(s.name),
              color: crmTaskStatusColor(s),
            ),
      ],
      onStatus: (name) {
        _tapChip(name);
        ref.read(followupGroupProvider.notifier).state = open;
      },
      trailing: [
        if (otherCount > 0 || selected.contains(crmTaskOtherChip))
          TabChip(
            label: 'Other / no status ($otherCount)',
            active: selected.contains(crmTaskOtherChip),
            onTap: () => _tapChip(crmTaskOtherChip),
          ),
      ],
    );
  }

  /// Webapp chip rules: "All" clears; statuses multi-select; Other exclusive.
  /// Anything but a lane leaves the picked group.
  void _tapChip(String k) {
    ref.read(followupGroupProvider.notifier).state = null;
    if (_deepLinkTabs.containsKey(k)) {
      ref.read(followupTabProvider.notifier).state = k;
      ref.read(followupChipsProvider.notifier).state = const {};
      return;
    }
    ref.read(followupTabProvider.notifier).state = 'all';
    ref
        .read(followupChipsProvider.notifier)
        .update((s) => toggleCrmTaskChip(s, k));
  }

  /// Webapp toolbar "Due date approvals (N)" — the same inbox as on Tasks; the
  /// server decides what each user may approve.
  Widget _approvalsLink() {
    if (!ApiConfig.apiEnabled) return const SizedBox.shrink();
    final n = ref.watch(pendingDueDateCountProvider);
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await context.push(Routes.dueDateApprovals);
          // A decision there changes what is still waiting, and the dates.
          if (mounted) {
            ref.invalidate(approvalCountsProvider);
            refreshFollowups(ref);
          }
        },
        child: Padding(
          padding: EdgeInsets.only(top: 10.h),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(PhosphorIconsRegular.sealCheck,
                size: 15.sp, color: AppColors.navy),
            SizedBox(width: 6.w),
            Text(n > 0 ? 'Due date approvals ($n)' : 'Due date approvals',
                style: AppText.captionStrong(color: AppColors.navy)),
          ]),
        ),
      ),
    );
  }

  /// The card's Call: opens the dialler on the phone of the record the
  /// follow-up is about (a lead or a customer), as the webapp's card does.
  Future<void> _callRelated(Followup f) async {
    final related = f.raw['related_to'];
    final model =
        related is Map ? '${related['model'] ?? ''}'.toLowerCase() : '';
    var id = related is Map ? '${related['id'] ?? ''}' : '';
    var isLead = model.contains('lead');
    if (id.isEmpty) {
      if ((f.leadId ?? '').isNotEmpty) {
        id = f.leadId!;
        isLead = true;
      } else if ((f.custId ?? '').isNotEmpty) {
        id = f.custId!;
        isLead = false;
      }
    }
    final name = _callee(f);
    if (id.isEmpty) {
      ref
          .read(toastProvider.notifier)
          .show('This follow-up has no related record to call.');
      return;
    }
    Map<String, dynamic>? row;
    try {
      row = isLead
          ? await ref.read(leadRowProvider(id).future)
          : await ref.read(customerRowProvider(id).future);
    } on Object {
      row = null;
    }
    if (!mounted) return;
    final p = row?['phone'] ?? row?['contact_phone'] ?? row?['mobile'];
    await dialCustomer(ref,
        phone: p is String ? p : '',
        name: name,
        what: isLead ? 'lead' : 'customer');
  }

  /// Who the card's Call button rings: the record the follow-up is about (the
  /// webapp card's call action), else its contact, else its title.
  String _callee(Followup f) {
    final related = f.raw['related_to'];
    final label =
        related is Map ? '${related['label'] ?? ''}'.trim() : f.contact.trim();
    return label.isNotEmpty ? label.split(' ').first : f.title;
  }

  /// Opens the Add follow-up sheet once its layout has settled — the sheet
  /// picks its form from a synchronous read, so opening mid-fetch would show
  /// the built-in one. Normally already resolved, so this yields and no more.
  Future<void> _openAddSheet(BuildContext ctx) async {
    await ref.read(followupFormReadyProvider.future);
    if (!mounted || !ctx.mounted) return;
    await showAddFollowupSheet(ctx, ref);
  }

  /// Pull-to-refresh: the rows, the org's follow-up types and task lanes, and
  /// both follow-up layouts (the card and the add/detail form). The catalogs and
  /// schemas are session-scoped, so this is the only way to pick up an admin's
  /// change short of a restart.
  Future<void> _refresh() async {
    refreshFollowups(ref);
    ref.invalidate(followupStatusCountsProvider);
    ref.invalidate(approvalCountsProvider);
    ref.invalidate(followupTypeCatalogProvider);
    ref.invalidate(taskStatusCatalogProvider);
    ref.invalidate(taskPriorityCatalogProvider);
    ref.invalidate(followupCardSchemaFutureProvider);
    ref.invalidate(followupDetailSchemaFutureProvider);
    // Gates the Add sheet on the org's form being ready; stale after the
    // schemas above are dropped.
    ref.invalidate(followupFormReadyProvider);
    await settle([
      ref.read(followupsQueriedProvider.future),
      ref.read(taskStatusCatalogProvider.future),
      ref.read(followupCardSchemaFutureProvider.future),
    ]);
  }

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    final spec = ref.read(followupsFilterSpecProvider);
    final current = ref.read(followupFiltersProvider);
    final base = ref.read(followupsAllProvider);
    final saved = ref.read(followupSavedFiltersProvider);
    final activeView = saved.active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      // Filters run server-side in API mode, so no device-side guess at the
      // count (webapp: "Apply filters").
      previewCount: ApiConfig.apiEnabled
          ? (_) => -1
          : (draft) =>
              base.where((f) => followupMatchesFilters(f, draft)).length,
      activeViewName: activeView?.name,
      existingViewNames: {for (final v in saved.filters) v.name},
      onSaveView: _saveView,
    );
    if (result == null) return;

    ref.read(followupFiltersProvider.notifier).state = result;
    // Webapp: applying the drawer leaves the saved view.
    if (activeView != null &&
        !sameFilterDefinition(
            ref.read(followupFilterCodecProvider).encode(result),
            activeView.definition)) {
      ref.read(followupSavedFiltersProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  /// Webapp: "View saved" / "View updated" (same name overwrites), empty
  /// filters refused with "Add at least one filter before saving.". The view
  /// is stored under `module=task`, so the Tasks list shows it too.
  Future<void> _saveView(String name, FilterValues draft) async {
    final toast = ref.read(toastProvider.notifier);
    final definition = ref.read(followupFilterCodecProvider).encode(draft);
    if (definition.isEmpty) {
      toast.showError('Add at least one filter before saving.');
      return;
    }
    final updating = ref
        .read(followupSavedFiltersProvider)
        .filters
        .any((f) => f.name.toLowerCase() == name.trim().toLowerCase());
    final error = await ref
        .read(followupSavedFiltersProvider.notifier)
        .save(name, definition);
    if (error != null) {
      toast.showError(error);
      return;
    }
    // The Tasks list keeps its own copy of the shared set.
    ref.invalidate(taskSavedFiltersProvider);
    toast.show(updating ? 'View updated' : 'View saved');
  }

  /// Deletes a saved view after the chip's confirm. Removing the applied view
  /// also clears its filters.
  Future<void> _removeView(String id) async {
    final wasActive = ref.read(followupSavedFiltersProvider).activeId == id;
    final error =
        await ref.read(followupSavedFiltersProvider.notifier).remove(id);
    if (error != null) {
      ref.read(toastProvider.notifier).showError(error);
      return;
    }
    ref.invalidate(taskSavedFiltersProvider);
    if (wasActive)
      ref.read(followupFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('View deleted');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(followupSavedFiltersProvider);
    return SizedBox(
      height: 34.h,
      child: chips.SavedChipRow(
        views: [for (final v in saved.filters) chips.SavedView(v.id, v.name)],
        active: {if (saved.activeId != null) saved.activeId!},
        showClearAlways: filterCount > 0,
        onToggle: _toggleView,
        onClear: _clearFilters,
        onRemove: _removeView,
      ),
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(followupSavedFiltersProvider);
    if (saved.activeId == id) {
      ref.read(followupSavedFiltersProvider.notifier).deactivate();
      ref.read(followupFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.filters.where((v) => v.id == id).firstOrNull;
    if (view == null) {
      ref
          .read(toastProvider.notifier)
          .show('That view is no longer available.');
      return;
    }
    // Webapp: applying a view fills the drawer and clears the status chips.
    ref.read(followupSavedFiltersProvider.notifier).apply(id);
    ref.read(followupChipsProvider.notifier).state = const {};
    ref.read(followupGroupProvider.notifier).state = null;
    ref.read(followupTabProvider.notifier).state = 'all';
    ref.read(followupFiltersProvider.notifier).state = ref
        .read(followupFilterCodecProvider)
        .decode(view.definition, ref.read(followupsFilterSpecProvider));
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  /// Whether a search, status chip or drawer filter is narrowing the list —
  /// the webapp then says "match your filters" instead of "yet".
  bool _isNarrowed() =>
      ref.read(followupSearchProvider).trim().isNotEmpty ||
      ref.read(followupFiltersProvider).activeCount > 0 ||
      ref.read(followupChipsProvider).isNotEmpty ||
      ref.read(followupGroupProvider) != null ||
      ref.read(followupTabProvider) != 'all';

  /// The empty state's "Clear filters": search, chip and drawer back to all.
  void _resetListView() {
    _searchCtrl.clear();
    ref.read(followupSearchProvider.notifier).state = '';
    ref.read(followupTabProvider.notifier).state = 'all';
    ref.read(followupChipsProvider.notifier).state = const {};
    ref.read(followupGroupProvider.notifier).state = null;
    _clearFilters();
  }

  void _clearFilters() {
    ref.read(followupSavedFiltersProvider.notifier).deactivate();
    ref.read(followupFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
