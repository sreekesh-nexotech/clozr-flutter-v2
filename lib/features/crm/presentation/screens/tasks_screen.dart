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
import '../../application/filters/tasks_filter_spec.dart';
import '../../application/filters/followups_filter_spec.dart' show followupSavedFiltersProvider;
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/crm_task.dart';
import '../components/task_card.dart';
import '../components/saved_chip_row.dart' as chips;
import '../../application/providers/saved_filters_providers.dart';
import 'due_date_approvals_screen.dart' show pendingDueDateCountProvider;

/// Tasks list — checkbox cards with status pills, wired to the spec-driven
/// filter engine and the contextual Add task sheet.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _searchCtrl = TextEditingController();

  /// The one tab that is not a status: the unfiltered list.
  ///
  /// "My tasks" and "Overdue" used to sit here too. They are not statuses —
  /// the backend has no such lane — so the row now shows the org's own statuses
  /// and nothing else.
  static const _pseudoTabs = <(String, String)>[
    ('all', 'All'),
  ];

  /// Labels for the non-status views that are still reachable from elsewhere.
  ///
  /// The CRM home "Tasks missed" card deep-links straight into `overdue`
  /// (`crm_home_screen.dart:543`). That view has no chip of its own any more, so
  /// without this the list would arrive filtered with nothing in the row
  /// selected — a short list and no visible reason for it. When such a view is
  /// active its chip is shown, selected, until the user picks another.
  static const _deepLinkTabs = <String, String>{
    'mine': 'My tasks',
    'overdue': 'Overdue',
  };

  /// The lanes shown in **API mode** while `crm-task-statuses` is in flight.
  ///
  /// These are the four statuses the backend seeds on every org — verified live
  /// against `GET /crm/crm-task-statuses/`, which returns exactly Open /
  /// In Progress / Completed / Cancelled with these colours (see
  /// `docs-flutter/task-schema-and-status-api.md` §2).
  ///
  /// Keyed by the **lane name**, not by the app's internal folded bucket: a
  /// task row carries its status as a display name ("In Progress"), and
  /// [crmTaskInTab] matches on that, so these chips filter correctly before the
  /// catalog lands *and* stay selected once it replaces them. Keying them by
  /// the folded buckets was what put the mock vocabulary on this row — and it
  /// merged Cancelled into `blocked`, so two lanes shared one chip.
  static const _seededLaneTabs = <(String, String, Color)>[
    ('Open', 'Open', Color(0xFF3B82F6)),
    ('In Progress', 'In Progress', Color(0xFFF59E0B)),
    ('Completed', 'Completed', Color(0xFF10B981)),
    ('Cancelled', 'Cancelled', Color(0xFF6B7280)),
  ];

  /// The lanes shown in **mock mode**, where rows carry no org lane name and
  /// only the built-in folded buckets exist to filter on.
  static final _mockLaneTabs = <(String, String, Color)>[
    for (final k in const ['todo', 'inprogress', 'blocked', 'done'])
      (k, StatusMeta$.task[k]!.label, StatusMeta$.task[k]!.color),
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
    // Coming back to Tasks: the rows, card layout and lanes were loaded on an
    // earlier visit and would otherwise be shown as they were then. Re-fetch
    // them, keeping the current cards on screen until the fresh ones arrive.
    // Skipped on the first visit, whose fetches are already in flight.
    if (ref.read(crmTasksProvider).hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(crmTasksProvider);
        ref.invalidate(taskListSchemaFutureProvider);
        ref.invalidate(taskStatusCatalogProvider);
      });
    }
    // Webapp: the saved filters are re-read whenever the list mounts. Loading
    // them only once per session left the chips missing for good if that one
    // call failed (offline, a timeout).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(taskSavedFiltersProvider.notifier).load();
    });
    // A query left behind by a collapsed box would filter the list with
    // nothing on screen saying so; only keep it while the box is open.
    if (!ref.read(crmTaskSearchOpenProvider) && ref.read(crmTaskSearchProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(crmTaskSearchProvider.notifier).state = '';
      });
    } else {
      _searchCtrl.text = ref.read(crmTaskSearchProvider);
    }
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
      // The org's own Task layout, not the built-in sheet's fixed field set —
      // the sheet collected five boxes and could not offer status, priority,
      // assignee, team or duration at all.
      AddAction(label: 'Add task', module: 'task', run: (ctx) => ctx.push(Routes.addCrmTask)),
    );

    // Counts come from the server-filtered rows (search, drawer, saved view)
    // and ignore the chip selection — the webapp's board counts.
    final all = ApiConfig.apiEnabled ? ref.watch(crmTasksBaseProvider) : ref.watch(crmTasksAllProvider);
    final async = ApiConfig.apiEnabled ? ref.watch(crmTasksQueriedProvider) : ref.watch(crmTasksProvider);
    final tab = ref.watch(crmTaskTabProvider);
    final selected = ref.watch(crmTaskChipsProvider);
    final searchOpen = ref.watch(crmTaskSearchOpenProvider);
    final query = ref.watch(crmTaskSearchProvider);
    final filterCount = ref.watch(crmTaskFiltersProvider).activeCount;
    // Watched purely to start the type/priority catalog fetches at mount.
    // Nothing else here references them, so without this the drawer would
    // snapshot them unloaded and fall back to the built-in vocabularies.
    ref.watch(taskTypeOptionsProvider);
    ref.watch(taskPriorityOptionsProvider);
    // Kept loaded for the drawer: the server's task assignees and teams.
    ref.watch(assignableUsersForModuleProvider('task'));
    ref.watch(assignableTeamsForModuleProvider('task'));

    // The org's own lanes drive the tab row — names, order, colour and count,
    // straight from `GET /crm/crm-task-statuses/`. Empty (still loading, failed
    // fetch, mock mode) falls back per mode: the seeded lane names in API mode,
    // the built-in vocabulary only where there is no API to disagree with.
    final statuses = ref.watch(taskStatusOptionsProvider);
    final otherCount = all.where((t) => crmTaskInNoLane(t, statuses)).length;
    final tabs = <(String, String, Color?)>[
      for (final (k, lbl) in _pseudoTabs) (k, lbl, null),
      if (_deepLinkTabs.containsKey(tab)) (tab, _deepLinkTabs[tab]!, null),
      if (statuses.isNotEmpty)
        for (final s in statuses) (s.name, s.name, crmTaskStatusColor(s))
      else if (ApiConfig.apiEnabled)
        ..._seededLaneTabs
      else
        ..._mockLaneTabs,
    ];
    // The org's list-card layout: which of the card's slots to render.
    final cardSchema = ref.watch(taskListSchemaProvider);

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
              onSearch: () {
                // Collapsing the box drops the query, like clearing the webapp's
                // search box — a hidden query would keep narrowing the list.
                if (searchOpen) {
                  _searchCtrl.clear();
                  ref.read(crmTaskSearchProvider.notifier).state = '';
                }
                ref.read(crmTaskSearchOpenProvider.notifier).state = !searchOpen;
              },
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
                  for (final (k, lbl, dot) in tabs)
                    TabChip(
                      label: '$lbl (${crmTaskTabCount(all, k)})',
                      dotColor: dot,
                      active: k == 'all'
                          ? tab == 'all' && selected.isEmpty
                          : _deepLinkTabs.containsKey(k)
                              ? tab == k
                              : selected.contains(k) || (selected.isEmpty && _tabActive(tab, k, statuses)),
                      onTap: () => _tapChip(k),
                    ),
                  // Webapp "Other / no status": only when some task sits in no
                  // lane, or it is selected.
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
            // Webapp: the row shows once there is a saved filter or a filter
            // applied.
            if (ref.watch(taskSavedFiltersProvider).filters.isNotEmpty ||
                filterCount > 0 ||
                ref.watch(taskSavedFiltersProvider).activeId != null) ...[
              SizedBox(height: 12.h),
              _savedViewRow(filterCount),
            ],
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<CrmTask>>(
            value: async,
            onRetry: () => ref.invalidate(crmTasksProvider),
            onRefresh: _refresh,
            data: (_) {
              final visible = ref.watch(visibleCrmTasksProvider);
              if (visible.isEmpty) {
                return ListView(
                  // So the gesture still works with nothing to scroll.
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _isNarrowed()
                        ? EmptyState(
                            icon: PhosphorIconsRegular.funnel,
                            title: 'No tasks match your filters',
                            body: 'Try widening your search or clearing a filter to see more.',
                            ctaLabel: 'Clear filters',
                            ctaIcon: PhosphorIconsBold.xCircle,
                            onCta: _resetListView,
                          )
                        : EmptyState(
                            icon: PhosphorIconsRegular.funnel,
                            title: 'No tasks yet',
                            body: 'Tasks track the work your team needs to get done. Add your first one to get started.',
                            ctaLabel: 'Add task',
                            ctaIcon: PhosphorIconsBold.plus,
                            onCta: () => context.push(Routes.addCrmTask),
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
                separatorBuilder: (_, __) => SizedBox(height: 12.h),
                itemBuilder: (context, i) {
                  final t = visible[i];
                  return TaskCard(
                    task: t,
                    schema: cardSchema,
                    onTap: () => context.push('${Routes.taskDetail}?id=${t.id}'),
                    onCall: () => ref.read(toastProvider.notifier).show('Calling ${_callee(t)}…'),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Webapp chip rules: "All" clears; statuses multi-select; Other exclusive.
  void _tapChip(String k) {
    if (_deepLinkTabs.containsKey(k)) {
      ref.read(crmTaskTabProvider.notifier).state = k;
      ref.read(crmTaskChipsProvider.notifier).state = const {};
      return;
    }
    ref.read(crmTaskTabProvider.notifier).state = 'all';
    ref.read(crmTaskChipsProvider.notifier).update((s) => toggleCrmTaskChip(s, k));
  }

  /// Webapp toolbar "Due date approvals (N)" — shown to everyone; the server
  /// decides what each user may approve.
  Widget _approvalsLink() {
    if (!ApiConfig.apiEnabled) return const SizedBox.shrink();
    final n = ref.watch(pendingDueDateCountProvider).valueOrNull ?? 0;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await context.push(Routes.dueDateApprovals);
          // A decision there changes what is still waiting.
          if (mounted) ref.invalidate(pendingDueDateCountProvider);
        },
        child: Padding(
          padding: EdgeInsets.only(top: 10.h),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(PhosphorIconsRegular.sealCheck, size: 15.sp, color: AppColors.navy),
            SizedBox(width: 6.w),
            Text(n > 0 ? 'Due date approvals ($n)' : 'Due date approvals', style: AppText.captionStrong(color: AppColors.navy)),
          ]),
        ),
      ),
    );
  }

  /// Who the card's Call button rings: the record the task is about (the
  /// webapp card's call action), else the task's title.
  String _callee(CrmTask t) {
    final related = t.raw['related_to'];
    final label = related is Map ? '${related['label'] ?? ''}'.trim() : '';
    return label.isNotEmpty ? label.split(' ').first : t.titleClean;
  }

  // ── Filter drawer ──
  /// Pull-to-refresh: the rows, the org's lanes / types / priorities and the
  /// card layout. All three of the latter are session-scoped and nothing else
  /// invalidates them, so a pull is the only way to pick up an admin's change
  /// without restarting.
  Future<void> _refresh() async {
    ref.invalidate(crmTasksProvider);
    ref.invalidate(pendingDueDateCountProvider);
    ref.invalidate(taskStatusCatalogProvider);
    ref.invalidate(taskTypeCatalogProvider);
    ref.invalidate(taskPriorityCatalogProvider);
    ref.invalidate(taskListSchemaFutureProvider);
    await settle([
      ref.read(crmTasksProvider.future),
      ref.read(taskStatusCatalogProvider.future),
      ref.read(taskListSchemaFutureProvider.future),
      // Reloaded through the controller, not invalidated: it also holds which
      // view is applied, and that is the user's choice, not server state.
      ref.read(taskSavedFiltersProvider.notifier).load(),
    ]);
  }

  Future<void> _openFilters() async {
    final spec = ref.read(crmTasksFilterSpecProvider);
    final current = ref.read(crmTaskFiltersProvider);
    final base = ref.read(crmTasksAllProvider);
    final saved = ref.read(taskSavedFiltersProvider);
    final activeView = saved.active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      // Filters run server-side in API mode, so no device-side guess at the
      // count (webapp: "Apply filters").
      previewCount: ApiConfig.apiEnabled
          ? (_) => -1
          : (draft) => base.where((t) => crmTaskMatchesFilters(t, draft)).length,
      activeViewName: activeView?.name,
      existingViewNames: {for (final v in saved.filters) v.name},
      onSaveView: _saveView,
    );
    if (result == null) return;

    ref.read(crmTaskFiltersProvider.notifier).state = result;
    // Webapp: applying the drawer leaves the saved view.
    if (activeView != null &&
        !sameFilterDefinition(ref.read(taskFilterCodecProvider).encode(result), activeView.definition)) {
      ref.read(taskSavedFiltersProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  /// Webapp: "View saved" / "View updated" (same name overwrites), empty
  /// filters refused with "Add at least one filter before saving.".
  Future<void> _saveView(String name, FilterValues draft) async {
    final toast = ref.read(toastProvider.notifier);
    final definition = ref.read(taskFilterCodecProvider).encode(draft);
    if (definition.isEmpty) {
      toast.showError('Add at least one filter before saving.');
      return;
    }
    final updating = ref.read(taskSavedFiltersProvider).filters.any((f) => f.name.toLowerCase() == name.trim().toLowerCase());
    final error = await ref.read(taskSavedFiltersProvider.notifier).save(name, definition);
    if (error != null) {
      toast.showError(error);
      return;
    }
    // Follow-ups show the same `module=task` set from their own copy.
    ref.invalidate(followupSavedFiltersProvider);
    toast.show(updating ? 'View updated' : 'View saved');
  }

  /// Deletes a saved view after the chip's × and confirm.
  Future<void> _removeView(String id) async {
    final wasActive = ref.read(taskSavedFiltersProvider).activeId == id;
    final error = await ref.read(taskSavedFiltersProvider.notifier).remove(id);
    if (error != null) {
      ref.read(toastProvider.notifier).showError(error);
      return;
    }
    ref.invalidate(followupSavedFiltersProvider);
    // Webapp: deleting the applied filter only drops the chip; its filters stay
    // applied, so the list does not change under the user.
    if (wasActive) ref.read(taskSavedFiltersProvider.notifier).deactivate();
    ref.read(toastProvider.notifier).show('View deleted');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(taskSavedFiltersProvider);
    return SizedBox(
      height: 34.h,
      child: chips.SavedChipRow(
        views: [for (final v in saved.filters) chips.SavedView(v.id, v.name)],
        active: {if (saved.activeId != null) saved.activeId!},
        showClearAlways: filterCount > 0,
        onToggle: _toggleView,
        onClear: _clearFilters,
        onRemove: _removeView,
        webappStyle: true,
      ),
    );
  }

  /// Webapp `applyPreset`: a tap applies the view — tapping the applied one
  /// applies it again (it is turned off with Clear filters).
  void _toggleView(String id) {
    final saved = ref.read(taskSavedFiltersProvider);
    final view = saved.filters.where((v) => v.id == id).firstOrNull;
    if (view == null) {
      ref.read(toastProvider.notifier).show('That view is no longer available.');
      return;
    }
    // Webapp: applying a view fills the drawer and clears the status chips.
    ref.read(taskSavedFiltersProvider.notifier).apply(id);
    ref.read(crmTaskChipsProvider.notifier).state = const {};
    ref.read(crmTaskFiltersProvider.notifier).state =
        ref.read(taskFilterCodecProvider).decode(view.definition, ref.read(crmTasksFilterSpecProvider));
  }

  /// Whether a search, status chip or drawer filter is narrowing the list —
  /// the webapp then says "match your filters" instead of "yet".
  bool _isNarrowed() =>
      ref.read(crmTaskSearchProvider).trim().isNotEmpty ||
      ref.read(crmTaskFiltersProvider).activeCount > 0 ||
      ref.read(crmTaskChipsProvider).isNotEmpty ||
      ref.read(crmTaskTabProvider) != 'all';

  /// The empty state's "Clear filters": search, chip and drawer back to all.
  void _resetListView() {
    _searchCtrl.clear();
    ref.read(crmTaskSearchProvider.notifier).state = '';
    ref.read(crmTaskTabProvider.notifier).state = 'all';
    ref.read(crmTaskChipsProvider.notifier).state = const {};
    _clearFilters();
  }

  void _clearFilters() {
    ref.read(taskSavedFiltersProvider.notifier).deactivate();
    ref.read(crmTaskFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
