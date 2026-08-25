import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
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
      AddAction(label: 'New task', run: (ctx) => ctx.push(Routes.createTask)),
    );

    // The **filtered** fetch: this is what the list renders, so its loading and
    // error states are the ones the screen must show. Watching the unfiltered
    // provider meant a filter change re-queried invisibly with stale rows up.
    final opsTasksAsync = ref.watch(opsTasksFilteredProvider);
    final base = ref.watch(otBaseProvider);
    final all = ref.watch(opsTasksListProvider);
    final projects = ref.watch(allProjectsProvider);
    final tab = ref.watch(otTabProvider);
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
    final tabDefs = <(String, String)>[
      ('all', 'All'),
      if (statusCatalog.isEmpty)
        for (final k in StatusMeta$.opsTask.keys) (k, StatusMeta$.opsTask[k]!.label)
      else
        for (final s in statusCatalog) (s.name, s.name),
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
                      label: '$label (${counts[k] ?? otTabCount(base, k, mine: mine)})',
                      active: tab == k,
                      onTap: () => ref.read(otTabProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _savedViewRow(mine, filterCount),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<OpsTask>>(
            value: opsTasksAsync,
            onRetry: () => ref.invalidate(opsTasksScopedProvider),
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
                      children: const [
                        EmptyState(
                          icon: PhosphorIconsRegular.listChecks,
                          title: 'No tasks found',
                          body: 'Try a different status, clear filters, or turn off "My Tasks" to see the whole team\'s work.',
                        ),
                      ],
                    )
                  : ListView.separated(
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
  /// Applies a filter set to the list. The query it is about to watch is dropped
  /// first, so re-applying a combination fetched earlier really re-queries.
  void _applyFilters(FilterValues values) {
    final params = opsTaskFilterParamsFor(
      values: values,
      codec: ref.read(opsTaskFilterCodecProvider),
      mine: ref.read(myTasksFProvider),
      search: ref.read(otSearchDebouncedProvider),
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
    final base = ref.read(otBaseProvider);
    final activeView = ref.read(opsTaskSavedFiltersProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((t) => opsTaskMatchesFilters(t, draft)).length,
      activeViewName: activeView?.name,
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
    final saved = ref.read(opsTaskSavedFiltersProvider);
    if (saved.activeId == id) {
      // Tapping the active view deactivates it and clears the applied filters.
      ref.read(opsTaskSavedFiltersProvider.notifier).deactivate();
      _applyFilters(FilterValues());
      return;
    }
    final view = saved.filters.firstWhere((f) => f.id == id);
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

  void _clearFilters() {
    ref.read(opsTaskSavedFiltersProvider.notifier).deactivate();
    _applyFilters(FilterValues());
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
