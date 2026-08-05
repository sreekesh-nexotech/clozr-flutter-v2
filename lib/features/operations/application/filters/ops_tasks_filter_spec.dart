import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
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
    {List<AppUser>? roster}) {
  final statuses = [
    for (final k in StatusMeta$.opsTask.keys) FilterOption(id: k, label: StatusMeta$.opsTask[k]!.label),
  ];
  final projectOpts = [
    for (final p in projects) FilterOption(id: p.id, label: p.name),
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
        const FilterField(
            id: 'pri',
            label: 'Priority',
            control: FilterControl.checkboxGroup,
            options: [
              FilterOption(id: 'High', label: 'High'),
              FilterOption(id: 'Medium', label: 'Medium'),
              FilterOption(id: 'Low', label: 'Low'),
            ]),
        const FilterField(
            id: 'types',
            label: 'Task type',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: [
              FilterOption(id: 'Task', label: 'Task'),
              FilterOption(id: 'Approval', label: 'Approval'),
              FilterOption(id: 'Site visit', label: 'Site visit'),
              FilterOption(id: 'Meeting', label: 'Meeting'),
            ]),
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

/// The task type. The entity carries no explicit type yet, so — as in the
/// prototype (`t.ttype || 'Task'`) — every task reads as a plain "Task".
String opsTaskType(OpsTask t) => 'Task';

/// Evaluate an ops task against applied filter values.
bool opsTaskMatchesFilters(OpsTask t, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('statuses'), [t.status])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('pri'), [t.pri])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('types'), [opsTaskType(t)])) return false;

  final milestone = v.radio('milestone');
  if (milestone != null && milestone.isActive) {
    if (milestone.id == 'yes' && !t.milestone) return false;
    if (milestone.id == 'no' && t.milestone) return false;
  }

  if (!FilterMatch.matchAnyOf(v.choice('projects'), [t.projId])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('groups'), [t.group])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('assignees'), t.assignees)) return false;
  if (!FilterMatch.matchAnyOf(v.choice('depts'), [t.dept])) return false;

  if (!FilterMatch.matchDate(v.date('due'), opsTaskDueDate(t))) return false;
  if (!FilterMatch.matchRange(v.range('hours'), t.expHrs, scale: 1)) return false;

  return true;
}

// ── Providers ──

/// The Ops Tasks drawer spec, derived from the loaded task + project catalogs.
final opsTasksFilterSpecProvider = Provider<FilterSpec>((ref) {
  return buildOpsTasksFilterSpec(
    ref.watch(opsTasksListProvider),
    ref.watch(projectsListProvider),
    roster: ref.watch(rosterProvider),
  );
});

/// Applied drawer filters for the Ops Tasks list (the source of the badge count).
final opsTaskFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Ops Tasks list (bookmark chips).
final opsTaskSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
