import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/api/status_keys.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/tasks_filter_spec.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/crm_task.dart';
import '../components/task_card.dart';
import '../components/saved_chip_row.dart' as chips;
import '../sheets/add_task_sheet.dart';

/// Tasks list — checkbox cards with status pills, wired to the spec-driven
/// filter engine and the contextual Add task sheet.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _searchCtrl = TextEditingController();

  /// Tabs that are not statuses at all — these stay built-in.
  static const _pseudoTabs = <(String, String)>[
    ('all', 'All'),
    ('mine', 'My tasks'),
    ('overdue', 'Overdue'),
  ];

  /// The built-in lane vocabulary, used **only** until the org's own arrives.
  ///
  /// A fallback, not the source of truth: these are the four folded buckets, so
  /// an org whose lanes are Open / In Progress / Completed / Cancelled would
  /// read "To do" / "Blocked" / "Done" — names it does not use.
  static const _builtinLaneTabs = <(String, String)>[
    ('todo', 'To do'),
    ('inprogress', 'In Progress'),
    ('blocked', 'Blocked'),
    ('done', 'Done'),
  ];

  /// Whether a chip should read as selected.
  ///
  /// Tolerant on purpose: the catalog can land after the user has already
  /// picked a built-in lane, swapping "To do" for the org's "Open". Matching
  /// the folded key as well keeps that chip highlighted through the swap
  /// instead of leaving the row with nothing selected.
  bool _tabActive(String tab, String chipKey, List<CatalogOption> statuses) {
    if (tab == chipKey) return true;
    for (final s in statuses) {
      if (s.name == chipKey &&
          crmTaskStatusKey(name: s.name, type: s.statusType) == tab) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(crmTaskSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Add task sheet here.
    registerAdd(
      ref,
      AddAction(label: 'Add task', run: (ctx) => showAddTaskSheet(ctx, ref)),
    );

    final all = ref.watch(crmTasksAllProvider);
    final async = ref.watch(crmTasksProvider);
    final tab = ref.watch(crmTaskTabProvider);
    final searchOpen = ref.watch(crmTaskSearchOpenProvider);
    final query = ref.watch(crmTaskSearchProvider);
    final filterCount = ref.watch(crmTaskFiltersProvider).activeCount;
    // Watched purely to start the type/priority catalog fetches at mount.
    // Nothing else here references them, so without this the drawer would
    // snapshot them unloaded and fall back to the built-in vocabularies.
    ref.watch(taskTypeOptionsProvider);
    ref.watch(taskPriorityOptionsProvider);
    final leads = ref.watch(leadsProvider).valueOrNull ?? const [];

    // The org's own lanes drive the tab row — names, order and count. Empty
    // (mock mode, still loading, failed fetch) falls back to the built-in
    // vocabulary, the same "empty schema is no opinion" contract used
    // everywhere else.
    final statuses = ref.watch(taskStatusOptionsProvider);
    final tabs = [
      ..._pseudoTabs,
      if (statuses.isEmpty)
        ..._builtinLaneTabs
      else
        for (final s in statuses) (s.name, s.name),
    ];
    // The org's list-card layout: which of the card's slots to render.
    final cardSchema = ref.watch(taskListSchemaProvider);

    String? relatedLineFor(String? leadId) {
      if (leadId == null) return null;
      for (final l in leads) {
        if (l.id == leadId) return '${l.company ?? l.name} · #${l.id}';
      }
      return null;
    }

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
              onSearch: () => ref.read(crmTaskSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search tasks…',
                onChanged: (v) => ref.read(crmTaskSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(crmTaskSearchProvider.notifier).state = '';
                  ref.read(crmTaskSearchOpenProvider.notifier).state = false;
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
                      label: '$lbl (${crmTaskTabCount(all, k)})',
                      active: _tabActive(tab, k, statuses),
                      onTap: () => ref.read(crmTaskTabProvider.notifier).state = k,
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
          child: AsyncStateView<List<CrmTask>>(
            value: async,
            onRetry: () => ref.invalidate(crmTasksProvider),
            data: (_) {
              final visible = ref.watch(visibleCrmTasksProvider);
              if (visible.isEmpty) {
                return ListView(
                  children: [
                    EmptyState(
                      icon: PhosphorIconsRegular.funnel,
                      title: 'No tasks found',
                      body: 'Try a different status, clear filters, or add a new task.',
                      ctaLabel: 'Add task',
                      ctaIcon: PhosphorIconsBold.plus,
                      onCta: () => showAddTaskSheet(context, ref),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                itemCount: visible.length,
                separatorBuilder: (_, __) => SizedBox(height: 12.h),
                itemBuilder: (context, i) {
                  final t = visible[i];
                  return TaskCard(
                    task: t,
                    schema: cardSchema,
                    relatedLine: relatedLineFor(t.leadId),
                    onTap: () => context.push('${Routes.taskDetail}?id=${t.id}'),
                    onToggle: () => _toggleTask(t),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Toggles a task's done state with an optimistic override. In API mode the
  /// write is awaited: on failure the override is rolled back to its prior value
  /// and the error is surfaced; the success toast fires only after the write
  /// lands. Mock mode is unchanged (optimistic + success toast).
  Future<void> _toggleTask(CrmTask t) async {
    final done = t.status == 'done';
    final newStatus = done ? 'todo' : 'done';
    final prev = ref.read(crmTaskStatusOverrideProvider);
    ref.read(crmTaskStatusOverrideProvider.notifier).state = {...prev, t.id: newStatus};
    if (ApiConfig.apiEnabled) {
      try {
        await ref.read(crmTasksRepositoryProvider).setTaskStatusByKey(t.id, newStatus);
      } on AppError catch (e) {
        final rolled = {...ref.read(crmTaskStatusOverrideProvider)};
        if (prev.containsKey(t.id)) {
          rolled[t.id] = prev[t.id]!;
        } else {
          rolled.remove(t.id);
        }
        ref.read(crmTaskStatusOverrideProvider.notifier).state = rolled;
        ref.read(toastProvider.notifier).show(e.message);
        return;
      }
    }
    ref.read(toastProvider.notifier).show(done ? 'Task reopened' : 'Task marked complete');
  }

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    final spec = ref.read(crmTasksFilterSpecProvider);
    final current = ref.read(crmTaskFiltersProvider);
    final base = ref.read(crmTasksAllProvider);
    final activeView = ref.read(crmTaskSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((t) => crmTaskMatchesFilters(t, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: (name, draft) {
        ref.read(crmTaskSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(crmTaskFiltersProvider.notifier).state = result;
    final views = ref.read(crmTaskSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(crmTaskSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(crmTaskSavedViewsProvider);
    return SizedBox(
      height: 34.h,
      child: chips.SavedChipRow(
        views: [for (final v in saved.views) chips.SavedView(v.id, v.name)],
        active: {if (saved.activeId != null) saved.activeId!},
        showClearAlways: filterCount > 0,
        onToggle: _toggleView,
        onClear: _clearFilters,
      ),
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(crmTaskSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(crmTaskSavedViewsProvider.notifier).deactivate();
      ref.read(crmTaskFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(crmTaskSavedViewsProvider.notifier).apply(id);
    ref.read(crmTaskFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(crmTaskSavedViewsProvider.notifier).clearActive();
    ref.read(crmTaskFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
