import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/crm_task.dart';
import '../providers/crm_catalog_providers.dart';
import '../providers/leads_providers.dart';
import '../providers/saved_filters_providers.dart';
import '../../../../data/api/user_directory.dart';

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
  List<CatalogOption> statusCatalog = const [],
  List<CatalogOption> teamCatalog = const [],
  List<CatalogOption> assignableUsers = const [],
  String title = 'Filter tasks by:',
  List<String> builtinTypes = kBuiltinTaskTypes,
}) {
  // Webapp: the users the server lets own a task (module=task), else the roster.
  final users = assignableUsers.isNotEmpty
      ? [for (final u in assignableUsers) FilterOption(id: u.id, label: u.name)]
      : [for (final u in roster) FilterOption(id: u.id, label: u.name)];
  // The server's own choice set when it has loaded. The option id is the
  // `task_type` **value**, which is what a row carries.
  final types = [
    for (final t in typeCatalog.isNotEmpty
        ? [for (final c in typeCatalog) c.id]
        : builtinTypes)
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
    title: title,
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
      if (statusCatalog.isNotEmpty)
        FilterSection(title: 'Status', fields: [
          FilterField(
              id: 'statuses',
              label: 'Status',
              control: FilterControl.searchSelect,
              searchable: true,
              isNotToggle: true,
              placeholder: 'Search status…',
              options: [for (final s in statusCatalog) FilterOption(id: s.id, label: s.name, dot: s.color)]),
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
            isNotToggle: true,
            options: priorities),
      ]),
      if (teamCatalog.isNotEmpty)
        FilterSection(title: 'Team', fields: [
          FilterField(
              id: 'teams',
              label: 'Team',
              control: FilterControl.searchSelect,
              searchable: true,
              isNotToggle: true,
              placeholder: 'Search team…',
              options: [for (final t in teamCatalog) FilterOption(id: t.id, label: t.name)]),
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

/// The drawer as the webapp's list params (`buildTaskFilterParams`) — also the
/// `filter_definition` a saved view stores.
class TaskFilterCodec {
  const TaskFilterCodec({this.statuses = const [], this.priorities = const []});

  final List<CatalogOption> statuses;
  final List<CatalogOption> priorities;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> encode(FilterValues v) {
    final out = <String, dynamic>{};
    final a = v.choice('assignees');
    if (a != null && a.ids.isNotEmpty) {
      final ids = [for (final id in a.ids) UserDirectory.realUserId(id) ?? id];
      out['assigned_to${a.isNot ? '__not' : '__in'}'] = ids.join(',');
    }
    // Webapp asymmetry: "is" sends status NAMES, "is not" sends ids.
    final st = v.choice('statuses');
    if (st != null && st.ids.isNotEmpty) {
      if (st.isNot) {
        out['status__not'] = st.ids.join(',');
      } else {
        final names = [
          for (final id in st.ids)
            for (final s in statuses)
              if (s.id == id) s.name,
        ];
        if (names.isNotEmpty) out['status__in'] = names.join(',');
      }
    }
    final p = v.choice('priorities');
    if (p != null && p.ids.isNotEmpty) {
      final ids = <String>[
        for (final label in p.ids)
          for (final c in priorities)
            if (priorityKey(c.name) == label || c.id == label) c.id,
      ];
      if (ids.isNotEmpty) out['priority${p.isNot ? '__not' : '__in'}'] = ids.join(',');
    }
    final t = v.choice('teams');
    if (t != null && t.ids.isNotEmpty) out['assigned_team${t.isNot ? '__not' : '__in'}'] = t.ids.join(',');
    final ty = v.choice('types');
    if (ty != null && ty.ids.isNotEmpty) out['task_type__in'] = ty.ids.join(',');
    final due = v.date('due');
    if (due != null && due.isActive) {
      if (due.from != null || due.to != null) {
        if (due.from != null) out['due_date_after'] = _ymd(due.from!);
        if (due.to != null) out['due_date_before'] = _ymd(due.to!);
      } else if (due.chip == 'overdue') {
        out['is_overdue'] = 'true';
      } else if (due.chip != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final n = due.chip == 'today'
            ? 0
            : due.chip == 'tomorrow'
                ? 1
                : int.tryParse(due.chip!.replaceFirst('next', '')) ?? 0;
        final after = due.chip == 'tomorrow' ? today.add(const Duration(days: 1)) : today;
        out['due_date_after'] = _ymd(after);
        out['due_date_before'] = _ymd(today.add(Duration(days: n)));
      }
    }
    return out;
  }

  /// The drawer option a stored user id belongs to. The Assignee list keys
  /// people by their real user id when the org's assignable users have loaded,
  /// and by the roster's ids (the signed-in user as `me`) otherwise — so a
  /// saved filter on yourself must come back as whichever the list uses, or
  /// it is counted as selected while no name shows ticked.
  static String _assigneeOptionId(String userId, FilterSpec spec) {
    for (final section in spec.sections) {
      for (final f in section.fields) {
        if (f.id != 'assignees') continue;
        if (f.options.any((o) => o.id == userId)) return userId;
      }
    }
    return UserDirectory.mapUserId(userId);
  }

  /// A stored definition back into drawer values. Quick due chips come back as
  /// their dates; only `is_overdue` returns as the Overdue chip (webapp).
  FilterValues decode(Map<String, dynamic> def, FilterSpec spec) {
    final v = spec.defaults();
    Set<String> ids(Object? raw) => {
          for (final p in '${raw ?? ''}'.split(','))
            if (p.trim().isNotEmpty) p.trim(),
        };
    for (final isNot in [false, true]) {
      final sfx = isNot ? '__not' : '__in';
      final a = ids(def['assigned_to$sfx']);
      if (a.isNotEmpty) v['assignees'] = ChoiceValue(ids: {for (final i in a) _assigneeOptionId(i, spec)}, isNot: isNot);
      final p = ids(def['priority$sfx']);
      if (p.isNotEmpty) {
        v['priorities'] = ChoiceValue(ids: {
          for (final i in p)
            for (final c in priorities)
              if (c.id == i) priorityKey(c.name),
        }, isNot: isNot);
      }
      final t = ids(def['assigned_team$sfx']);
      if (t.isNotEmpty) v['teams'] = ChoiceValue(ids: t, isNot: isNot);
    }
    final sIn = ids(def['status__in']);
    if (sIn.isNotEmpty) {
      v['statuses'] = ChoiceValue(ids: {
        for (final n in sIn)
          for (final s in statuses)
            if (s.name.toLowerCase() == n.toLowerCase()) s.id,
      });
    }
    final sNot = ids(def['status__not']);
    if (sNot.isNotEmpty) v['statuses'] = ChoiceValue(ids: sNot, isNot: true);
    final ty = ids(def['task_type__in']);
    if (ty.isNotEmpty) v['types'] = ChoiceValue(ids: ty);
    if ('${def['is_overdue']}' == 'true') {
      v['due'] = const DateValue(chip: 'overdue');
    } else {
      final after = DateTime.tryParse('${def['due_date_after'] ?? ''}');
      final before = DateTime.tryParse('${def['due_date_before'] ?? ''}');
      if (after != null || before != null) v['due'] = DateValue(from: after, to: before);
    }
    return v;
  }
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
    statusCatalog: ref.watch(taskStatusOptionsProvider),
    teamCatalog: ref.watch(assignableTeamsForModuleProvider('task')).valueOrNull ?? const [],
    assignableUsers: ref.watch(assignableUsersForModuleProvider('task')).valueOrNull ?? const [],
  ),
);

final taskFilterCodecProvider = Provider<TaskFilterCodec>((ref) => TaskFilterCodec(
      statuses: ref.watch(taskStatusOptionsProvider),
      priorities: ref.watch(taskPriorityOptionsProvider),
    ));

/// Saved views on the Tasks list, backed by `/crm/saved-filters/?module=task`.
final taskSavedFiltersProvider = StateNotifierProvider<SavedFiltersController, SavedFiltersState>(
  (ref) => SavedFiltersController(module: 'task', remote: ref.watch(savedFiltersRemoteProvider)),
);

/// Applied drawer filters for the Tasks list (the source of the badge count).
final crmTaskFiltersProvider = StateProvider<FilterValues>((ref) {
  // A new sign-in rebuilds the API service; the next user starts unfiltered.
  ref.watch(apiServiceProvider);
  return FilterValues();
});

/// Saved views for the Tasks list (bookmark chips).
final crmTaskSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
