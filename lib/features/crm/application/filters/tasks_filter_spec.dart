import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/crm_task.dart';

/// Tasks filter — spec-driven drawer (audit §3). Wired exactly like the Leads
/// reference: spec provider → applied provider → matcher → saved views.
///
/// Sections and options come straight from the audit: Assignee (Search & Select
/// + is/is not), Task type (2-col, icons), Priority (inline, icons), Due date.

const List<String> _taskTypes = [
  'Call',
  'Email',
  'Meeting',
  'WhatsApp',
  'Site visit',
  'Follow-up',
  'Payment',
];

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
FilterSpec buildTasksFilterSpec() {
  final users = [
    for (final u in MockUsers.reps) FilterOption(id: u.id, label: u.name),
  ];
  final types = [
    for (final t in _taskTypes) FilterOption(id: t, label: t),
  ];
  final priorities = [
    FilterOption(id: 'High', label: 'High', dot: StatusMeta$.priorityTone['High']!.fg),
    FilterOption(id: 'Medium', label: 'Medium', dot: StatusMeta$.priorityTone['Medium']!.fg),
    FilterOption(id: 'Low', label: 'Low', dot: StatusMeta$.priorityTone['Low']!.fg),
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

/// The Tasks drawer spec.
final crmTasksFilterSpecProvider = Provider<FilterSpec>((ref) => buildTasksFilterSpec());

/// Applied drawer filters for the Tasks list (the source of the badge count).
final crmTaskFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Tasks list (bookmark chips).
final crmTaskSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
