import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../crm/presentation/screens/due_date_approvals_screen.dart' show pendingDueDateCountProvider;
import '../../infrastructure/data_sources/remote/ops_tasks_remote_ds.dart';
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
import '../../../crm/application/providers/saved_filters_providers.dart';
import '../../../crm/presentation/components/saved_chip_row.dart' as chips;
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../../../core/config/api_config.dart';
import '../../application/filters/ops_tasks_filter_spec.dart';
import '../../application/providers/ops_tasks_providers.dart';
import '../../application/providers/projects_providers.dart';
import '../../domain/entities/ops_task.dart';
import '../components/ops_task_card.dart';
import '../components/ops_widgets.dart';

/// Ops Tasks list — status tabs + a "My Tasks" saved-view chip + saved-view
/// bookmark row over a scrolling list of task cards. Wired to the spec-driven
/// filter engine (drawer → applied provider → matcher → badge → saved views),
/// following the Leads reference.
class OpsTasksScreen extends ConsumerStatefulWidget {
  const OpsTasksScreen({super.key});

  @override
  ConsumerState<OpsTasksScreen> createState() => _OpsTasksScreenState();
}

class _OpsTasksScreenState extends ConsumerState<OpsTasksScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(otSearchProvider);
    // A dashboard KPI that counts a slice of the tasks (overdue, due today, …)
    // links here with `?due=<chip>` so the list opens on that slice. Applied
    // after the first frame: the filter state is a provider the build below
    // reads, so it cannot be set while this widget is still being inserted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Webapp refetches the saved views whenever the page opens.
      ref.read(opsTaskSavedFiltersProvider.notifier).load();
      final params = GoRouterState.of(context).uri.queryParameters;
      // Project detail › "View all tasks": this project's tasks, everyone's
      // (webapp opens Operations › Tasks with the project pre-selected).
      final project = params['project'];
      if (project != null && project.isNotEmpty) {
        ref.read(myTasksFProvider.notifier).state = false;
        final values = ref.read(opsTaskFiltersProvider).copy();
        values['projects'] = ChoiceValue(ids: {project});
        _applyFilters(values);
        return;
      }
      final due = params['due'];
      if (due == null || due.isEmpty) return;
      // The dashboard counts across the whole org ("Across all projects"),
      // so the slice it links to is everyone's tasks, not just mine.
      ref.read(myTasksFProvider.notifier).state = false;
      final values = ref.read(opsTaskFiltersProvider).copy();
      values['due'] = DateValue(chip: due);
      _applyFilters(values);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the create-task form here (#10).
    registerAdd(
      ref,
      AddAction(
        label: 'New task',
        module: 'project_task',
        run: (ctx) => ctx.push(Routes.createTask),
      ),
    );

    // The **filtered** fetch: this is what the list renders, so its loading and
    // error states are the ones the screen must show. Watching the unfiltered
    // provider meant a filter change re-queried invisibly with stale rows up.
    final opsTasksAsync = ref.watch(opsTasksFilteredProvider);
    final base = ref.watch(otBaseProvider);
    final all = ref.watch(opsTasksListProvider);
    final projects = ref.watch(allProjectsProvider);
    final tabs = ref.watch(otTabsProvider);
    final mine = ref.watch(myTasksFProvider);
    final searchOpen = ref.watch(otSearchOpenProvider);
    final query = ref.watch(otSearchProvider);
    final filters = ref.watch(opsTaskFiltersProvider);
    final filterCount = filters.activeCount;

    // Server-side tab counts. Empty (mock mode, a failed call, or the my-tasks
    // scope the aggregate miscounts) means each tab counts the rows on hand.
    final counts = ref.watch(opsTaskStatusCountsProvider).valueOrNull ??
        const <String, int>{};

    // The org's own statuses drive the tab strip. Empty (still loading, failed
    // fetch, mock mode) falls back to the built-in vocabulary.
    final statusCatalog = ref.watch(opsTaskStatusOptionsProvider);
    // Webapp `buildTaskStatusTabs`: All, the active statuses by position, "Other
    // / no status" only when it holds tasks, and the date-rule Overdue last.
    final otherCount = counts[OpsTasksRemoteDataSource.otherTab] ?? 0;
    final tabDefs = <(String, String)>[
      ('all', 'All'),
      if (statusCatalog.isEmpty)
        for (final k in StatusMeta$.opsTask.keys) (k, StatusMeta$.opsTask[k]!.label)
      else
        for (final s in statusCatalog) (s.id, s.name),
      if (otherCount > 0) (OpsTasksRemoteDataSource.otherTab, 'Other / no status'),
      (OpsTasksRemoteDataSource.overdueTab, 'Overdue'),
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
              title: 'Tasks',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () => ref.read(otSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search tasks…',
                onChanged: (v) => ref.read(otSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(otSearchProvider.notifier).state = '';
                  ref.read(otSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 10.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final (k, label) in tabDefs)
                    TabChip(
                      label: '$label (${counts[k] ?? otTabCount(base, k)})',
                      active: k == 'all' ? tabs.isEmpty : tabs.contains(k),
                      onTap: () => ref.read(otTabsProvider.notifier).state = toggleOpsTaskTab(tabs, k),
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _savedViewRow(mine, filterCount),
            _approvalsLink(),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<OpsTask>>(
            value: opsTasksAsync,
            onRetry: () => ref.invalidate(opsTasksScopedProvider),
            onRefresh: _refresh,
            data: (_) {
              final tabVisible = ref.watch(visibleOpsTasksProvider);
              final visible = filters.isEmpty
                  ? tabVisible
                  : tabVisible
                      .where((t) => opsTaskMatchesFilters(t, filters,
                          serverApplied: ApiConfig.apiEnabled))
                      .toList();
              return visible.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [_emptyState(mine, filterCount)],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => SizedBox(height: 12.h),
                      itemBuilder: (context, i) {
                        final t = visible[i];
                        return OpsTaskCard(
                          task: t,
                          projectName: opsTaskProjectName(t, projects),
                          unresolvedCount: unresolvedDepCount(t, all),
                          onTap: () => context.push('${Routes.opsTaskDetail}?id=${t.id}'),
                          onMore: _canUpdate(t) || _canDelete(t) ? () => _rowMenu(t) : null,
                        );
                      },
                    );
            },
          ),
        ),
      ],
    );
  }

  /// Pull-to-refresh. Reloads the currently filtered rows together with the
  /// status catalog and tab counts, so a pull also picks up an admin's change
  /// to the org's own task statuses while the app is running.
  Future<void> _refresh() async {
    ref.invalidate(opsTasksScopedProvider(OpsTaskListQuery(
      filters: ref.read(opsTaskListParamsProvider),
    )));
    ref.invalidate(opsTaskStatusCatalogProvider);
    ref.invalidate(opsTaskStatusCountsProvider);
    ref.invalidate(pendingDueDateCountProvider);
    await settle([
      ref.read(opsTasksFilteredProvider.future),
      ref.read(opsTaskStatusCatalogProvider.future),
      ref.read(opsTaskStatusCountsProvider.future),
      // Reloaded through the controller: it also holds which view is applied.
      ref.read(opsTaskSavedFiltersProvider.notifier).load(),
    ]);
  }

  // ── Filter drawer ──
  /// Applies a filter set to the list. The query it is about to watch is dropped
  /// first, so re-applying a combination fetched earlier really re-queries.
  void _applyFilters(FilterValues values) {
    final params = opsTaskListParamsFor(
      opsTaskFilterParamsFor(
        values: values,
        codec: ref.read(opsTaskFilterCodecProvider),
        mine: ref.read(myTasksFProvider),
        search: ref.read(otSearchDebouncedProvider),
      ),
      ref.read(otTabsProvider),
      ref.read(opsTaskStatusOptionsProvider),
    );
    ref.invalidate(opsTasksScopedProvider(OpsTaskListQuery(filters: params)));
    ref.read(opsTaskFiltersProvider.notifier).state = values;
  }

  Future<void> _openFilters() async {
    // The sheet takes its spec once and keeps it, so the catalog must be settled
    // before it opens. Normally already resolved — the fetch starts at mount.
    await ref.read(opsTaskFilterCatalogsProvider.future);
    if (!mounted) return;
    final spec = ref.read(opsTasksFilterSpecProvider);
    final current = ref.read(opsTaskFiltersProvider);
    // The "Apply · N results" preview counts the draft against every task in
    // the current My Tasks / search scope — not the list on screen, which the
    // applied filters already narrowed (an "is not" then previewed 0).
    var base = ref.read(otBaseProvider);
    if (ApiConfig.apiEnabled) {
      final scope = opsTaskFilterParamsFor(
        values: FilterValues(),
        codec: ref.read(opsTaskFilterCodecProvider),
        mine: ref.read(myTasksFProvider),
        search: ref.read(otSearchDebouncedProvider),
      );
      try {
        base = await ref.read(opsTasksScopedProvider(OpsTaskListQuery(filters: scope)).future);
      } on Object {
        // Keep the list on screen.
      }
      if (!mounted) return;
    }
    final activeView = ref.read(opsTaskSavedFiltersProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((t) => opsTaskMatchesFilters(t, draft)).length,
      activeViewName: activeView?.name,
      existingViewNames: ref.read(opsTaskSavedFiltersProvider).filters.map((f) => f.name).toSet(),
      onSaveView: _saveView,
    );
    if (result == null) return;

    _applyFilters(result);
    // A manual Apply deactivates the active saved view unless the draft still
    // means the same thing. Compared as encoded definitions, since that is what
    // the view actually stores.
    final active = ref.read(opsTaskSavedFiltersProvider).active;
    if (active != null) {
      final encoded = ref.read(opsTaskFilterCodecProvider).encode(result);
      if (!sameFilterDefinition(encoded, active.definition)) {
        ref.read(opsTaskSavedFiltersProvider.notifier).deactivate();
      }
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  /// Persists the drawer draft as a saved filter on `/crm/saved-filters/`.
  ///
  /// The API stores the backend's own param dict, so the draft is encoded
  /// before it is sent; rejections (duplicate name, the 5-per-module limit, an
  /// unknown filter key) come back as user-safe text and are shown as-is.
  Future<void> _saveView(String name, FilterValues draft) async {
    final definition = ref.read(opsTaskFilterCodecProvider).encode(draft);
    final error =
        await ref.read(opsTaskSavedFiltersProvider.notifier).save(name, definition);
    if (!mounted) return;
    ref.read(toastProvider.notifier).show(error ?? 'View "$name" saved');
  }

  // ── Saved-view row: My Tasks toggle + saved bookmark chips + Clear ──
  Widget _savedViewRow(bool mine, int filterCount) {
    final saved = ref.watch(opsTaskSavedFiltersProvider);
    return SizedBox(
      height: 34.h,
      child: Row(
        children: [
          OpsSavedChip(
            label: 'My Tasks',
            active: mine,
            onTap: () {
              // `my_tasks=true` is a server scope, so flipping it changes the
              // query key rather than re-filtering rows already on screen.
              ref.read(myTasksFProvider.notifier).state = !mine;
              _applyFilters(ref.read(opsTaskFiltersProvider));
            },
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: chips.SavedChipRow(
              views: [for (final f in saved.filters) chips.SavedView(f.id, f.name)],
              active: {if (saved.activeId != null) saved.activeId!},
              // Webapp: Clear shows while anything narrows the list — facets,
              // a view, My Tasks or a status tab.
              showClearAlways: filterCount > 0 || mine || ref.watch(otTabsProvider).isNotEmpty,
              onToggle: _toggleView,
              onClear: _clearFilters,
              onRemove: _removeView,
              webappStyle: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleView(String id) async {
    final saved = ref.read(opsTaskSavedFiltersProvider);
    if (saved.activeId == id) {
      // Tapping the active view deactivates it and clears the applied filters.
      ref.read(opsTaskSavedFiltersProvider.notifier).deactivate();
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
    // A filter the server marked invalid fails inert by contract — never run
    // it, say why instead.
    if (!view.isValid) {
      ref.read(toastProvider.notifier).show(
            'View "${view.name}" refers to a field that no longer exists.',
          );
      return;
    }
    // A chip is tappable without ever opening the drawer, so wait for the same
    // catalog here: decoding maps stored status ids back to drawer options, and
    // a half-loaded catalog would drop them.
    await ref.read(opsTaskFilterCatalogsProvider.future);
    if (!mounted) return;

    final values = ref
        .read(opsTaskFilterCodecProvider)
        .decode(view.definition, ref.read(opsTasksFilterSpecProvider));
    ref.read(opsTaskSavedFiltersProvider.notifier).apply(id);
    _applyFilters(values);
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  /// Webapp `clearAllFilters`: the facets, the applied view, My Tasks, the
  /// status tabs and the search all go.
  void _clearFilters() {
    ref.read(opsTaskSavedFiltersProvider.notifier).deactivate();
    ref.read(myTasksFProvider.notifier).state = false;
    ref.read(otTabsProvider.notifier).state = const {};
    _searchCtrl.clear();
    ref.read(otSearchProvider.notifier).state = '';
    _applyFilters(FilterValues());
    ref.read(toastProvider.notifier).show('Filters cleared');
  }

  /// Webapp `removePreset`: DELETE the saved filter → "View deleted". Deleting
  /// the applied one only drops the chip; its filters stay applied.
  Future<void> _removeView(String id) async {
    final wasActive = ref.read(opsTaskSavedFiltersProvider).activeId == id;
    final error = await ref.read(opsTaskSavedFiltersProvider.notifier).remove(id);
    if (!mounted) return;
    if (error != null) {
      ref.read(toastProvider.notifier).showError(error);
      return;
    }
    if (wasActive) ref.read(opsTaskSavedFiltersProvider.notifier).deactivate();
    ref.read(toastProvider.notifier).show('View deleted');
  }

  /// The webapp's three empty states: filters that match nothing (with Clear
  /// filters), My Tasks with nothing assigned (with New Task), and none at all.
  Widget _emptyState(bool mine, int filterCount) {
    final narrowing = filterCount > 0 ||
        ref.read(opsTaskSavedFiltersProvider).activeId != null ||
        ref.read(otTabsProvider).isNotEmpty ||
        ref.read(otSearchProvider).trim().isNotEmpty;
    if (narrowing) {
      return EmptyState(
        icon: PhosphorIconsRegular.magnifyingGlassMinus,
        title: 'No tasks match your filters',
        body: 'Try widening your search or clearing a filter to see more.',
        ctaLabel: 'Clear filters',
        ctaIcon: PhosphorIconsBold.x,
        onCta: _clearFilters,
      );
    }
    final canCreate = hasPermission(ref, 'project_task', PermVerb.create);
    return EmptyState(
      icon: PhosphorIconsRegular.clipboardText,
      title: mine ? 'No tasks assigned to you' : 'No tasks yet',
      body: mine
          ? 'Nothing is assigned to you yet. Create a task, or clear the "My Tasks" filter to see the whole team\'s work.'
          : 'Tasks break a project down into the work your team delivers. Create your first one to get started.',
      ctaLabel: canCreate ? 'New Task' : null,
      ctaIcon: PhosphorIconsBold.plus,
      onCta: () => context.push(Routes.createTask),
    );
  }

  /// Webapp toolbar "Due date approvals (N)" — the manager's inbox, N being
  /// the changes waiting on this user.
  Widget _approvalsLink() {
    if (!ApiConfig.apiEnabled) return const SizedBox.shrink();
    final n = ref.watch(pendingDueDateCountProvider).valueOrNull ?? 0;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await context.push(Routes.dueDateApprovals);
          if (mounted) ref.invalidate(pendingDueDateCountProvider);
        },
        child: Padding(
          padding: EdgeInsets.only(top: 10.h),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(PhosphorIconsRegular.sealCheck, size: 15.sp, color: AppColors.navy),
            SizedBox(width: 6.w),
            Text(n > 0 ? 'Due date approvals ($n)' : 'Due date approvals',
                style: AppText.captionStrong(color: AppColors.navy)),
          ]),
        ),
      ),
    );
  }

  // ── Row ⋯ menu (webapp `RowMenu`) ──
  bool _canUpdate(OpsTask t) =>
      t.canUpdate != false && hasPermission(ref, 'project_task', PermVerb.update);
  bool _canDelete(OpsTask t) =>
      t.canDelete != false && hasPermission(ref, 'project_task', PermVerb.delete);

  Future<void> _rowMenu(OpsTask t) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      // Above the shell's bottom nav, which otherwise covers the last row.
      useRootNavigator: true,
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 8.h),
          if (_canUpdate(t)) ...[
            ListTile(
              leading: Icon(PhosphorIconsRegular.pencilSimple, size: 18.sp),
              title: const Text('Edit'),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            ListTile(
              leading: Icon(PhosphorIconsRegular.flag, size: 18.sp),
              title: Text(t.milestone ? 'Clear milestone' : 'Mark milestone'),
              onTap: () => Navigator.of(ctx).pop('milestone'),
            ),
          ],
          if (_canDelete(t))
            ListTile(
              leading: Icon(PhosphorIconsRegular.trash, size: 18.sp, color: AppColors.error),
              title: Text('Delete', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          SizedBox(height: 8.h),
        ]),
      ),
    );
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'edit':
        context.push('${Routes.editTask}?id=${t.id}');
      case 'milestone':
        if (await _rowWrite(() => ref
            .read(opsTasksRepositoryProvider)
            .updateOpsTask(t.id, {'is_milestone': !t.milestone}))) {
          ref.read(toastProvider.notifier).show(t.milestone ? 'Milestone cleared' : 'Marked as milestone');
        }
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete this task?'),
            content: Text('This permanently removes "${t.subject}". Remove its dependencies and '
                'subtasks first if it\'s blocking others.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Delete', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        if (await _rowWrite(() => ref.read(opsTasksRepositoryProvider).deleteOpsTask(t.id))) {
          ref.read(toastProvider.notifier).show('Task deleted');
        }
    }
  }

  /// A row write; the server's refusal is one toast. The list and the tab
  /// counts refetch off the write tick.
  Future<bool> _rowWrite(Future<void> Function() call) async {
    try {
      await call();
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) ref.read(toastProvider.notifier).showError(e.bareMessage);
      return false;
    }
    return mounted;
  }
}
