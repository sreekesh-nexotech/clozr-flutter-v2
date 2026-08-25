import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../domain/entities/ops_task.dart';
import '../../domain/entities/project.dart';
import '../providers/ops_tasks_providers.dart';
import '../providers/projects_providers.dart';

/// Ops Tasks filter — spec-driven engine wiring for the Operations Tasks list
/// (ported 1:1 from the prototype's `_fspec.opsTasks`). Follows the Leads
/// reference: build a [FilterSpec] from the loaded data, expose it plus an
/// applied-values provider and a saved-views controller, and match rows with the
/// pure [FilterMatch] helpers.

/// The task's due date (ISO preferred).
DateTime? opsTaskDueDate(OpsTask t) => DateTime.tryParse(t.endISO);

/// Build the Ops Tasks drawer spec from the current task + project sets. [roster]
/// supplies the assignee options (real members in API mode, prototype reps in
/// mock mode); null defaults to the mock reps.
FilterSpec buildOpsTasksFilterSpec(List<OpsTask> tasks, List<Project> projects,
    {List<AppUser>? roster,
    List<CatalogOption> statusCatalog = const [],}) {
  final statuses = [
    // The org's own statuses when the catalog has loaded, the built-in
    // vocabulary otherwise. The built-ins are only right by accident: an org
    // renames its task lanes freely.
    if (statusCatalog.isEmpty)
      for (final k in StatusMeta$.opsTask.keys)
        FilterOption(id: k, label: StatusMeta$.opsTask[k]!.label)
    else
      for (final s in statusCatalog) FilterOption(id: s.name, label: s.name),
  ];
  final projectOpts = [
    for (final p in projects) FilterOption(id: p.id, label: p.name),
  ];
  // Task types, keyed by the `task_type_id` the `type__in` param wants and
  // labelled with the org's own `task_type_name`. Derived from the loaded rows
  // because no task-type catalog endpoint is documented — this replaced a
  // hardcoded Task / Approval / Site visit / Meeting list that matched nothing.
  final typeById = <String, String>{};
  for (final t in tasks) {
    if (t.typeId.isNotEmpty && t.typeName.isNotEmpty) typeById[t.typeId] = t.typeName;
  }
  final types = [
    for (final e in typeById.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)))
      FilterOption(id: e.key, label: e.value),
  ];
  final groups = (tasks.map((t) => t.group).where((g) => g.isNotEmpty).toSet().toList()..sort())
      .map((g) => FilterOption(id: g, label: g))
      .toList();
  final depts = (tasks.map((t) => t.dept).where((d) => d.isNotEmpty).toSet().toList()..sort())
      .map((d) => FilterOption(id: d, label: d))
      .toList();
  final users = [
    for (final u in (roster ?? MockUsers.reps)) FilterOption(id: u.id, label: u.name),
  ];

  return FilterSpec(
    title: 'Filter tasks by:',
    sections: [
      FilterSection(title: 'Task information', fields: [
        FilterField(
            id: 'statuses',
            label: 'Status',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: statuses),
        // Four levels, not three: the backend's set is Urgent | High | Medium |
        // Low and `priority__in=Urgent` is accepted (verified against the dev
        // API). Without the option an urgent task could not be filtered to, and
        // [priorityKey] folds to `'Urgent'` regardless of what the drawer offers.
        const FilterField(
            id: 'pri',
            label: 'Priority',
            control: FilterControl.checkboxGroup,
            options: [
              FilterOption(id: 'Urgent', label: 'Urgent'),
              FilterOption(id: 'High', label: 'High'),
              FilterOption(id: 'Medium', label: 'Medium'),
              FilterOption(id: 'Low', label: 'Low'),
            ]),
        // Derived facets are omitted when the loaded rows yield nothing rather
        // than rendering as a labelled void: `type`/`task_type_name` are in the
        // slim projection but null until the org defines task types.
        if (types.isNotEmpty)
          FilterField(
              id: 'types',
              label: 'Task type',
              control: FilterControl.checkboxGroup,
              twoCol: true,
              options: types),
        const FilterField(
            id: 'milestone',
            label: 'Milestone',
            control: FilterControl.radio,
            options: [
              FilterOption(id: 'any', label: 'Any'),
              FilterOption(id: 'yes', label: 'Milestones only'),
              FilterOption(id: 'no', label: 'Exclude milestones'),
            ]),
      ]),
      FilterSection(title: 'Project & ownership', fields: [
        FilterField(
            id: 'projects',
            label: 'Project',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search project…',
            options: projectOpts),
        if (groups.isNotEmpty)
          FilterField(
              id: 'groups',
              label: 'Task group',
              control: FilterControl.checkboxGroup,
              twoCol: true,
              options: groups),
        FilterField(
            id: 'assignees',
            label: 'Assignee',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search user…',
            options: users),
        // `department` is not in the `?view=list` projection at all (verified
        // against the dev API: the slim row carries 19 keys and that is not one
        // of them), so in API mode this list is always empty and the facet was
        // a heading with nothing under it. It still populates in mock mode,
        // where the seed rows carry a department.
        if (depts.isNotEmpty)
          FilterField(
              id: 'depts',
              label: 'Department',
              control: FilterControl.checkboxIsNot,
              isNotToggle: true,
              twoCol: true,
              options: depts),
      ]),
      FilterSection(title: 'Schedule', fields: [
        const FilterField(
            id: 'due',
            label: 'Due date',
            control: FilterControl.dateRange,
            dateChips: ['overdue', 'today', 'tomorrow', 'next7', 'next30', 'next60', 'next90']),
        // Expected time has no backing in API mode: the task shape carries no
        // hours/effort field and no param filters on one, so `expHrs` is always
        // 0 and the slider could only ever match everything or nothing. Offered
        // in mock mode alone, where the seed rows do carry hours.
        if (!ApiConfig.apiEnabled)
          const FilterField(
              id: 'hours',
              label: 'Expected time',
              control: FilterControl.numberRange,
              unit: 'hours',
              unitScale: 1),
      ]),
    ],
  );
}

/// The task's type id, which is what the drawer's options are keyed by.
///
/// This used to return the constant `'Task'` for every task (the prototype's
/// `t.ttype || 'Task'`), so the Type facet could only ever match everything or
/// nothing.
String opsTaskType(OpsTask t) => t.typeId;

/// Evaluate an ops task against applied filter values.
bool opsTaskMatchesFilters(OpsTask t, FilterValues v, {bool serverApplied = false}) {
  // Skipped when the server already ran them. Re-applying is not merely
  // redundant: the server matched on ids where these match on the display values
  // a row carries, so a renamed status would be filtered out twice and wrongly.
  if (!serverApplied) {
    if (!FilterMatch.matchAnyOf(
        v.choice('statuses'), [t.status, if (t.statusName.isNotEmpty) t.statusName])) {
      return false;
    }
    if (!FilterMatch.matchAnyOf(v.choice('pri'), [t.pri])) return false;
    if (!FilterMatch.matchAnyOf(v.choice('types'), [opsTaskType(t)])) return false;
    if (!FilterMatch.matchAnyOf(v.choice('projects'), [t.projId])) return false;
  }

  // "Milestones only" is encoded (`is_milestone=true`); "Exclude milestones" has
  // no documented param, so that side always runs here.
  final milestone = v.radio('milestone');
  if (milestone != null && milestone.isActive) {
    if (!serverApplied && milestone.id == 'yes' && !t.milestone) return false;
    if (milestone.id == 'no' && t.milestone) return false;
  }

  if (!FilterMatch.matchAnyOf(v.choice('groups'), [t.group])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('assignees'), t.assignees)) return false;
  if (!FilterMatch.matchAnyOf(v.choice('depts'), [t.dept])) return false;

  if (!FilterMatch.matchDate(v.date('due'), opsTaskDueDate(t))) return false;
  // Prototype-only field; an API row has no hours to match, so the facet lets
  // it through rather than filtering every task out.
  if (t.expHrs != null &&
      !FilterMatch.matchRange(v.range('hours'), t.expHrs!, scale: 1)) {
    return false;
  }

  return true;
}

// ── Providers ──

/// The Ops Tasks drawer spec, derived from the loaded task + project catalogs.
final opsTasksFilterSpecProvider = Provider<FilterSpec>((ref) {
  return buildOpsTasksFilterSpec(
    ref.watch(opsTasksListProvider),
    ref.watch(allProjectsProvider),
    roster: ref.watch(rosterProvider),
    statusCatalog: ref.watch(opsTaskStatusOptionsProvider),
  );
});

/// Applied drawer filters for the Ops Tasks list (the source of the badge count).
final opsTaskFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

// The saved-view chips are `opsTaskSavedFiltersProvider` in
// `crm/application/providers/saved_filters_providers.dart` — backed by
// `/crm/saved-filters/?module=project_task` so they survive a restart. The
// in-memory `SavedViewsController` that used to live here did not.
