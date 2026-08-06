import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/crm_task.dart';
import '../providers/crm_catalog_providers.dart';

/// Tasks filter — spec-driven drawer (audit §3). Wired exactly like the Leads
/// reference: spec provider → applied provider → matcher → saved views.
///
/// Sections and options come straight from the audit: Assignee (Search & Select
/// + is/is not), Task type (2-col, icons), Priority (inline, icons), Due date.

/// The built-in task-type vocabulary, used only until the org's own arrives.
///
/// A **fallback, not the source of truth**: task rows carry `task_type` as a
/// string and the matcher compares it exactly, so this list has to be the
/// server's own choice set. The canonical set is Task / Call / Meeting / Email
/// / Deadline — note `Task` is the default type, so a drawer missing it cannot
/// filter the most common row on the screen.
const List<String> kBuiltinTaskTypes = [
  'Task',
  'Call',
  'Meeting',
  'Email',
  'Deadline',
];

/// The built-in priority vocabulary — the folded display values the app shows
/// when the org catalog has not loaded. See [kBuiltinTaskTypes] for why this is
/// a fallback only.
const List<String> kBuiltinTaskPriorities = ['Urgent', 'High', 'Medium', 'Low'];

const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// Parse a CRM date display string ("16 Jun 2026", "24 Jun 2026 · 10:00",
/// "No due date") to a DateTime, or null when there is no parseable date.
DateTime? parseCrmDate(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('no due')) return null;
  final datePart = trimmed.split('·').first.trim();
  final parts = datePart.split(RegExp(r'\s+'));
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = _months[parts[1]];
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  return DateTime(year, month, day);
}

/// Build the Tasks drawer spec (audit §3). Option lists that the audit marks
/// admin-configurable are the audit's canonical set; the assignee list is the
/// full workspace roster.
FilterSpec buildTasksFilterSpec({
  List<AppUser> roster = MockUsers.reps,
  List<CatalogOption> typeCatalog = const [],
  List<CatalogOption> priorityCatalog = const [],
}) {
  final users = [
    for (final u in roster) FilterOption(id: u.id, label: u.name),
  ];
  // The server's own choice set when it has loaded. The option id is the
  // `task_type` **value**, which is what a row carries.
  final types = [
    for (final t in typeCatalog.isNotEmpty
        ? [for (final c in typeCatalog) c.id]
        : kBuiltinTaskTypes)
      FilterOption(id: t, label: t),
  ];
  // Priorities are folded to the built-in display vocabulary on the way in
  // (`priorityKey`), so the option ids must be folded the same way — otherwise
  // the org's lower-case "high" would never match a row's "High". Folding also
  // collapses duplicates, hence the de-dup.
  final priorityNames = priorityCatalog.isNotEmpty
      ? {for (final p in priorityCatalog) priorityKey(p.name)}.toList()
      : kBuiltinTaskPriorities;
  final priorities = [
    for (final p in priorityNames)
      FilterOption(
        id: p,
        label: p,
        dot: StatusMeta$.priorityTone[p]?.fg,
      ),
  ];

  return FilterSpec(
    title: 'Filter tasks by:',
    sections: [
      FilterSection(title: 'Assignee', fields: [
        FilterField(
            id: 'assignees',
            label: 'Assignee',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search user…',
            options: users),
      ]),
      FilterSection(title: 'Task type', fields: [
        FilterField(
            id: 'types',
            label: 'Task type',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: types),
      ]),
      FilterSection(title: 'Priority', fields: [
        FilterField(
            id: 'priorities',
            label: 'Priority',
            control: FilterControl.checkboxGroup,
            options: priorities),
      ]),
      FilterSection(title: 'Due date', fields: [
        const FilterField(
            id: 'due',
            label: 'Due date',
            control: FilterControl.dateRange,
            dateChips: ['overdue', 'today', 'tomorrow', 'next7', 'next30', 'next60', 'next90']),
      ]),
    ],
  );
}

/// Evaluate a task against applied filter values.
bool crmTaskMatchesFilters(CrmTask t, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('assignees'), [t.assignee])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('types'), [t.type])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('priorities'), [t.priority])) return false;
  if (!FilterMatch.matchDate(v.date('due'), parseCrmDate(t.due))) return false;
  return true;
}

// ── Providers ──

/// The Tasks drawer spec, with the org's own type and priority vocabularies.
final crmTasksFilterSpecProvider = Provider<FilterSpec>(
  (ref) => buildTasksFilterSpec(
    roster: ref.watch(rosterProvider),
    typeCatalog: ref.watch(taskTypeOptionsProvider),
    priorityCatalog: ref.watch(taskPriorityOptionsProvider),
  ),
);

/// Applied drawer filters for the Tasks list (the source of the badge count).
final crmTaskFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Tasks list (bookmark chips).
final crmTaskSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
