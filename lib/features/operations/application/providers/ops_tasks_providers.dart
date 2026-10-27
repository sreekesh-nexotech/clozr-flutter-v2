import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/paginated.dart';
import '../../../crm/application/providers/attachments_providers.dart';
import '../../../crm/domain/entities/audit_entry.dart';
import '../../../crm/domain/entities/lead_file.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../core/filters/filter_models.dart';
import '../filters/ops_task_filter_codec.dart';
import '../filters/ops_tasks_filter_spec.dart';
import '../../domain/entities/ops_task.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/ops_tasks_repository.dart';
import '../../infrastructure/data_sources/local/ops_tasks_mock_ds.dart';
import '../../infrastructure/data_sources/remote/ops_tasks_remote_ds.dart';
import '../../infrastructure/repositories/ops_tasks_api_repository.dart';
import '../../infrastructure/repositories/ops_tasks_repository_impl.dart';
import 'projects_providers.dart';

/// The prototype's `ohNow` — 09 Jul 2026, 09:41 — used for due-date deltas.
final DateTime kOpsNow = DateTime(2026, 7, 9, 9, 41);

/// A task is overdue when its end date has passed and it is neither completed
/// nor cancelled (the prototype's `isOverdueOt`).
bool isTaskOverdue(OpsTask t) {
  // The server already decided this against the real date and the org's own
  // closed statuses. Trust it: `kOpsToday` is the prototype's frozen clock
  // (9 Jul 2026), so anything due since then read as on-time forever.
  if (t.isOverdue != null) return t.isOverdue!;
  if (t.status == 'completed' || t.status == 'cancelled') return false;
  final end = DateTime.tryParse(t.endISO);
  return end != null && end.isBefore(kOpsToday);
}

/// The clock due-date deltas are measured from: the device's in API mode, the
/// prototype's frozen [kOpsNow] against the seed, whose dates only make sense
/// relative to it.
DateTime get opsNow => ApiConfig.apiEnabled ? DateTime.now() : kOpsNow;

/// A task date + time the webapp's way: "28 Jun, 17:00" (24-hour, the year
/// only when it is not the current one), "28 Jun" with no time, and "—" when
/// the task has no date at all — never a bare label.
///
/// [date] is the mapper's "28 Jun 2026" display form and [time] its "5:00 PM"
/// one, which the edit form also parses back, so it is reformatted here rather
/// than stored differently.
String opsWhenLabel(String date, String time) {
  final d = date.trim();
  if (d.isEmpty || d == '—') return '—';
  final parsed = _parseDisplayDate(d);
  final day = parsed == null
      ? d
      : DateFormat(parsed.year == DateTime.now().year ? 'd MMM' : 'd MMM yyyy').format(parsed);
  final m = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false).firstMatch(time.trim());
  if (m == null) return day;
  var h = int.parse(m.group(1)!) % 12;
  if (m.group(3)!.toUpperCase() == 'PM') h += 12;
  return '$day, ${h.toString().padLeft(2, '0')}:${m.group(2)}';
}

DateTime? _parseDisplayDate(String d) {
  for (final f in ['dd MMM yyyy', 'd MMM yyyy']) {
    try {
      return DateFormat(f).parseStrict(d);
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// The pill a task's status renders as — the twin of `projectStatusMeta`.
///
/// The org's own name **and colour** from `/projects/project-task-statuses/`
/// whenever the catalog has the status; the built-in vocabulary only stands in
/// while the catalog is loading or for a status since removed.
StatusMeta opsTaskStatusMeta({
  required String key,
  required String statusName,
  required List<CatalogOption> statuses,
}) {
  final fallback = StatusMeta$.opsTask[key] ?? StatusMeta$.opsTask['open']!;
  final needle = (statusName.trim().isNotEmpty ? statusName : key).trim().toLowerCase();
  for (final s in statuses) {
    if (s.name.trim().toLowerCase() == needle) {
      return StatusMeta(s.name, s.color ?? fallback.color);
    }
  }
  return statusName.trim().isEmpty ? fallback : StatusMeta(statusName.trim(), fallback.color);
}

/// Whole-day delta from now to the task's end-of-day (negative = overdue).
///
/// Two things this gets wrong if written the obvious way:
///
/// * `endISO` is **not** always a bare date. The seed carries "2026-05-20", but
///   `/projects/tasks/` returns a full timestamp ("2026-07-10T12:30:00Z"), and
///   appending `T23:59:59` to that produces an unparseable string. That parsed
///   to null and returned 0 — which every caller reads as "due today", so an
///   overdue task showed a "Today" chip and the overdue KPI counted none.
/// * Truncating the difference with `inDays` would round an overdue task back
///   to 0 (yesterday 23:59 minus now is only a few hours), so the floor is
///   taken over the raw milliseconds instead.
int taskDueDelta(OpsTask t) {
  final due = DateTime.tryParse(t.endISO);
  if (due == null) return 0;
  final local = due.toLocal();
  final endOfDay = DateTime(local.year, local.month, local.day, 23, 59, 59);
  final ms = endOfDay.difference(opsNow).inMilliseconds;
  return (ms / Duration.millisecondsPerDay).floor();
}

/// DI seam: mock-backed with no API base URL, remote-backed otherwise.
final opsTasksRepositoryProvider = Provider<OpsTasksRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const OpsTasksRepositoryImpl(OpsTasksMockDataSource());
  }
  return OpsTasksApiRepository(
    OpsTasksRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Async source of all ops tasks.
/// The org's project-task statuses — the tab strip and the drawer's Status facet.
final opsTaskStatusCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  if (!await opsModuleReadable(ref, 'project_task')) return const [];
  return ref.watch(opsTasksRepositoryProvider).getOpsTaskStatuses();
});

/// Synchronous view — empty while in flight, in mock mode and on failure, which
/// callers read as "use the built-in vocabulary".
final opsTaskStatusOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(opsTaskStatusCatalogProvider).valueOrNull ?? const [],
);

/// The status a subtask moves to when it is **ticked** — the first closed,
/// non-cancelled one (`operations.md` §13.4). Null when the catalog has not
/// loaded, which is the one case where the tick must refuse rather than guess.
final opsTaskDoneStatusProvider = Provider<CatalogOption?>((ref) => ref
    .watch(opsTaskStatusOptionsProvider)
    .where((s) => s.isClosed && !s.isCancelled)
    .firstOrNull);

/// The status a subtask moves to when it is **un-ticked** — the first open one.
final opsTaskOpenStatusProvider = Provider<CatalogOption?>((ref) =>
    ref.watch(opsTaskStatusOptionsProvider).where((s) => !s.isClosed).firstOrNull);

/// Every closed status id, which is what decides whether a fetched subtask row
/// reads as done. Cancelled counts: a cancelled subtask no longer blocks its
/// parent, so leaving it unticked would misreport the "N/M done" counter.
final opsTaskClosedStatusIdsProvider = Provider<Set<String>>((ref) => {
      for (final s in ref.watch(opsTaskStatusOptionsProvider))
        if (s.isClosed) s.id,
    });

/// The lanes on one project (`/projects/task-groups/?project=…`), for the
/// create/edit forms' Task-group picker. Keyed by project because groups are
/// defined per project — picking a different project must re-ask.
final taskGroupsProvider =
    FutureProvider.autoDispose.family<List<CatalogOption>, String>(
  (ref, projectId) =>
      ref.watch(opsTasksRepositoryProvider).getTaskGroups(projectId),
);

/// The org's task types — webapp `getTaskTypes()`, `GET /projects/task-types/`
/// (`{task_type_id, name}`), for the drawer's Type facet and the task forms.
/// Best-effort: empty on a failure or in mock mode.
final opsTaskTypeCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  if (!ApiConfig.apiEnabled) return const [];
  if (!await opsModuleReadable(ref, 'project_task')) return const [];
  try {
    final body = await ref
        .watch(apiServiceProvider)
        .get('/projects/task-types/', query: {'page_size': 100}, quiet: true);
    return [
      for (final r in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results)
        if ('${r['task_type_id'] ?? ''}'.isNotEmpty && r['is_active'] != false)
          CatalogOption(id: '${r['task_type_id']}', name: '${r['name'] ?? ''}'.trim()),
    ];
  } on Object {
    return const [];
  }
});

/// Every project's lanes (`GET /projects/task-groups/`), for the drawer's Task
/// group facet — keyed by `task_group_id` so the server filters on it, and
/// labelled "Lane · Project" since each project names its own lanes.
final opsTaskGroupCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  if (!ApiConfig.apiEnabled) return const [];
  if (!await opsModuleReadable(ref, 'project_task')) return const [];
  final projects = {for (final p in ref.watch(allProjectsProvider)) p.id: p.name};
  try {
    final body = await ref
        .watch(apiServiceProvider)
        .get(ApiEndpoints.taskGroups, query: {'page_size': 200}, quiet: true);
    final out = <CatalogOption>[];
    for (final r in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results) {
      final id = '${r['task_group_id'] ?? ''}';
      final title = '${r['title'] ?? ''}'.trim();
      if (id.isEmpty || title.isEmpty) continue;
      final p = r['project'];
      final project = '${r['project_name'] ?? (p is Map ? p['project_name'] : projects['$p']) ?? ''}'.trim();
      out.add(CatalogOption(id: id, name: project.isEmpty ? title : '$title · $project'));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  } on Object {
    return const [];
  }
});

/// The org's task types, keyed by the `task_type_id` that `type` wants on
/// write: the catalog once it has loaded, else the types the loaded rows carry.
final opsTaskTypeOptionsProvider = Provider<List<CatalogOption>>((ref) {
  final catalog = ref.watch(opsTaskTypeCatalogProvider).valueOrNull ?? const [];
  if (catalog.isNotEmpty) return catalog;
  final byId = <String, String>{};
  for (final t in ref.watch(opsTasksListProvider)) {
    if (t.typeId.isNotEmpty && t.typeName.isNotEmpty) byId[t.typeId] = t.typeName;
  }
  final out = [for (final e in byId.entries) CatalogOption(id: e.key, name: e.value)];
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
});

/// Started at mount by the list screen so the drawer never snapshots a
/// half-loaded catalog.
final opsTaskFilterCatalogsProvider = FutureProvider<void>((ref) async {
  await ref.watch(opsTaskStatusCatalogProvider.future);
  await ref.watch(opsTaskTypeCatalogProvider.future);
  await ref.watch(opsTaskGroupCatalogProvider.future);
});

/// The query key for one task fetch.
class OpsTaskListQuery {
  const OpsTaskListQuery({this.filters = const {}});

  final Map<String, dynamic> filters;

  String get signature {
    final keys = filters.keys.toList()..sort();
    return [for (final k in keys) '$k=${filters[k]}'].join('&');
  }

  @override
  bool operator ==(Object other) =>
      other is OpsTaskListQuery && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

/// Tasks for one query — the server does the filtering.
final opsTasksScopedProvider =
    FutureProvider.family<List<OpsTask>, OpsTaskListQuery>((ref, q) async {
  if (!await opsModuleReadable(ref, 'project_task')) return const <OpsTask>[];
  // Re-read after any successful write (a task created, edited, completed or
  // deleted, a project renamed or archived), as the webapp refetches its task
  // lists and counts after every task write.
  ref.watch(apiWriteTickProvider);
  return ref.watch(opsTasksRepositoryProvider).getOpsTasks(filters: q.filters);
});

/// Translates the Tasks drawer to the documented query params.
final opsTaskFilterCodecProvider = Provider<OpsTaskFilterCodec>(
  (ref) => OpsTaskFilterCodec(
    statuses: ref.watch(opsTaskStatusOptionsProvider),
    currentUserId: UserDirectory.currentUserId,
  ),
);

/// The server params the current drawer + My-tasks state produces.
///
/// `my_tasks=true` is the documented toggle (§1) — tasks the caller is on via
/// the primary assignee FK **or** the M2M, which is more than the local
/// `isMine` could ever see from a slim list row.
/// [search] is the header's own control, which used to be applied only to rows
/// already downloaded — so it could not find a task outside the loaded set.
/// `search` matches the subject server-side (§1).
///
/// The status **tabs** are not part of this: the counts are taken without
/// them, and [opsTaskListParamsProvider] adds them for the list alone.
Map<String, dynamic> opsTaskFilterParamsFor({
  required FilterValues values,
  required OpsTaskFilterCodec codec,
  required bool mine,
  String search = '',
}) {
  if (!ApiConfig.apiEnabled) return const {};
  return {
    if (mine) 'my_tasks': 'true',
    if (search.trim().isNotEmpty) 'search': search.trim(),
    ...codec.encode(values),
  };
}

final opsTaskFilterParamsProvider = Provider<Map<String, dynamic>>(
  (ref) => opsTaskFilterParamsFor(
    values: ref.watch(opsTaskFiltersProvider),
    codec: ref.watch(opsTaskFilterCodecProvider),
    mine: ref.watch(myTasksFProvider),
    search: ref.watch(otSearchDebouncedProvider),
  ),
);

/// The list's params: [opsTaskFilterParamsProvider] plus the selected status
/// tabs, as the webapp's `listFilterParams` sends them — status tabs OR'd as
/// `status__in=<ids>` (over the drawer's own status__in), Overdue as the date
/// rule `is_overdue=true`, and "Other / no status" as `status__not_in=<every
/// active status>` merged with any drawer "Status is not …".
Map<String, dynamic> opsTaskListParamsFor(
  Map<String, dynamic> filters,
  Set<String> tabs,
  List<CatalogOption> activeStatuses,
) {
  if (!ApiConfig.apiEnabled || tabs.isEmpty) return filters;
  final out = {...filters};
  if (tabs.contains(OpsTasksRemoteDataSource.overdueTab)) {
    out['is_overdue'] = 'true';
  } else if (tabs.contains(OpsTasksRemoteDataSource.otherTab)) {
    final drawer = '${out['status__not_in'] ?? ''}'
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    out['status__not_in'] = {...drawer, for (final s in activeStatuses) s.id}.join(',');
  } else {
    out['status__in'] = (tabs.toList()..sort()).join(',');
  }
  return out;
}

final opsTaskListParamsProvider = Provider<Map<String, dynamic>>(
  (ref) => opsTaskListParamsFor(
    ref.watch(opsTaskFilterParamsProvider),
    ref.watch(otTabsProvider),
    ref.watch(opsTaskStatusOptionsProvider),
  ),
);

/// The search box, settled.
///
/// The raw provider updates on every keystroke and drives the instant local
/// narrowing; this one lags it so the server sees one query per pause rather
/// than one per character.
final otSearchDebouncedProvider =
    StateNotifierProvider<_DebouncedSearch, String>((ref) => _DebouncedSearch(ref));

class _DebouncedSearch extends StateNotifier<String> {
  _DebouncedSearch(Ref ref) : super('') {
    ref.listen<String>(otSearchProvider, (_, next) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 350), () {
        if (mounted) state = next.trim();
      });
    });
  }

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The tab strip's counts, from `/projects/tasks/status-counts/` under the same
/// filters as the list.
///
/// Keyed by status id, plus `'all'` and the Overdue / Other tabs. Empty means
/// the strip falls back to counting the rows it has.
///
/// Asked with the same search, My Tasks and drawer params as the webapp's
/// `getTaskStatusCounts` — never the selected tabs, so picking one does not
/// zero the others.
final opsTaskStatusCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  if (!await opsModuleReadable(ref, 'project_task')) return const <String, int>{};
  ref.watch(apiWriteTickProvider);
  // The aggregate ignores `is_overdue` (the drawer's Due date › Overdue), so
  // under it the tabs count the rows the list returned instead.
  if (ref.watch(opsTaskFilterParamsProvider).containsKey('is_overdue')) return const {};
  return ref
      .watch(opsTasksRepositoryProvider)
      .getStatusCounts(ref.watch(opsTaskFilterParamsProvider));
});

/// Org-wide tasks — the cross-screen lookup source, so it ignores the list's
/// filters.
final opsTasksProvider = FutureProvider<List<OpsTask>>(
  (ref) => ref.watch(opsTasksScopedProvider(const OpsTaskListQuery()).future),
);

/// The Tasks list itself, with the drawer and the My-tasks scope resolved by the
/// server where the API supports it.
final opsTasksFilteredProvider = FutureProvider<List<OpsTask>>(
  (ref) => ref.watch(
    opsTasksScopedProvider(
      OpsTaskListQuery(filters: ref.watch(opsTaskListParamsProvider)),
    ).future,
  ),
);


/// Synchronous view of the loaded ops tasks (empty until loaded).
/// Synchronous view of the **org-wide** list — the cross-screen lookup source.
///
/// Deliberately unfiltered: the task detail screen resolves its task here, and
/// the project detail and ops home read it too. Pointing this at the filtered
/// fetch made those depend on whatever the Tasks *list* screen's drawer happened
/// to be set to — a task excluded by a filter became "not found" on its own
/// detail page.
final opsTasksListProvider = Provider<List<OpsTask>>(
  (ref) => ref.watch(opsTasksProvider).valueOrNull ?? const [],
);

/// The tasks belonging to one project — `GET /projects/tasks/?project={id}`,
/// verified live against dev.
///
/// Scoped server-side rather than filtered out of the org-wide list: that only
/// worked while every task happened to be loaded, and it made the project page
/// depend on the Tasks list screen's own fetch.
final projectTasksProvider =
    FutureProvider.autoDispose.family<List<OpsTask>, String>((ref, projectId) {
  if (projectId.isEmpty) return Future.value(const <OpsTask>[]);
  ref.watch(apiWriteTickProvider);
  return ref
      .watch(opsTasksRepositoryProvider)
      .getOpsTasks(filters: {'project': projectId});
});

/// Synchronous view of the **filtered** fetch — only the Tasks list screen.
final opsTasksFilteredListProvider = Provider<List<OpsTask>>(
  (ref) => ref.watch(opsTasksFilteredProvider).valueOrNull ?? const [],
);

/// One task in its full shape — `GET /projects/tasks/{id}/`.
final opsTaskDetailProvider =
    FutureProvider.autoDispose.family<OpsTask?, String>(
  (ref, id) {
    // Re-reads after any successful write, so an edit's own PATCH refreshes the
    // record it came from.
    ref.watch(apiWriteTickProvider);
    return ref.watch(opsTasksRepositoryProvider).getOpsTask(id);
  },
);

/// The files on one task — webapp `getTaskFiles`: `GET /crm/attachments/
/// ?related_to=project_task&related_to_id=<id>`. Refetched after any write.
final projectTaskFilesProvider =
    FutureProvider.autoDispose.family<List<LeadFile>, String>((ref, taskId) {
  ref.watch(apiWriteTickProvider);
  if (taskId.isEmpty) return Future.value(const <LeadFile>[]);
  return ref.watch(attachmentsRepositoryProvider).getFiles('project_task', taskId);
});

/// One task's audit trail — `GET /projects/tasks/{id}/activity/`
/// (`operations-task.md` §3B).
///
/// Not the org-wide `/access-control/audit-logs/` the CRM cards read: this feed
/// is gated by `view_task` alone, so it works for a PM the audit endpoint 403s.
///
/// Refetched off the API write tick, so a status change, an edit, a dependency
/// or a subtask tick made on the screen shows up without each action saying so.
/// Empty is the fallback — mock mode, a failure, or a task with no history —
/// and the card then does not render at all.
final opsTaskActivityProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, taskId) async {
  ref.watch(apiWriteTickProvider);
  // The catalog first: the server's own summary quotes the status **uuid**
  // ("Status changed to 7803f448-…"), so without these names the timeline shows
  // the user a raw id.
  await ref.watch(opsTaskStatusCatalogProvider.future);
  return ref.watch(opsTasksRepositoryProvider).getTaskActivity(
        taskId,
        statusNames: {
          for (final s in ref.read(opsTaskStatusOptionsProvider)) s.id: s.name,
        },
      );
});

/// The full record when it has arrived, the list row until then.
///
/// The edit form used to prefill from the list row alone, so the description,
/// expected start, department and blockers came up blank whatever was stored —
/// `?view=list` simply does not carry them.
final opsTaskDetailOrListProvider = Provider.autoDispose.family<OpsTask?, String>(
  (ref, id) =>
      ref.watch(opsTaskDetailProvider(id)).valueOrNull ??
      ref.watch(opsTaskByIdProvider(id)),
);

/// Look up a single ops task by id (detail screen).
final opsTaskByIdProvider = Provider.family<OpsTask?, String>((ref, id) {
  for (final t in ref.watch(opsTasksListProvider)) {
    if (t.id == id) return t;
  }
  return null;
});

// ── List UI state ──

// Each list control belongs to the signed-in session: watching the API gateway
// (rebuilt on every sign-in / sign-out) resets them, so the next user starts
// on the webapp defaults instead of the previous user's tab, search or scope.
T opsPerSession<T>(Ref ref, T initial) {
  ref.watch(apiServiceProvider);
  return initial;
}

/// The selected status tabs — empty is "All". Status ids (built-in keys in mock
/// mode), or one of the exclusive Overdue / Other tabs. Webapp `toggleTaskTab`.
final otTabsProvider =
    StateProvider<Set<String>>((ref) => opsPerSession(ref, const <String>{}));

/// Webapp `toggleTaskTab`: "All" clears; Overdue and Other are exclusive;
/// status tabs multi-select among themselves.
Set<String> toggleOpsTaskTab(Set<String> selected, String value) {
  if (value == 'all') return const {};
  bool special(String v) =>
      v == OpsTasksRemoteDataSource.overdueTab || v == OpsTasksRemoteDataSource.otherTab;
  if (special(value)) return selected.contains(value) ? const {} : {value};
  final plain = selected.where((v) => !special(v)).toSet();
  return plain.contains(value) ? (plain..remove(value)) : (plain..add(value));
}
final otSearchProvider = StateProvider<String>((ref) => opsPerSession(ref, ''));
final otSearchOpenProvider = StateProvider<bool>((ref) => opsPerSession(ref, false));

/// "My Tasks" saved-view default (on, mirroring `myTasksF: true`).
final myTasksFProvider = StateProvider<bool>((ref) => opsPerSession(ref, true));

/// Ops-home "My Tasks" sort segment — 'priority' (default) or 'due'.
final opsSortProvider = StateProvider<String>((ref) => 'priority');

/// Base list before the status tab (respects the My/All view).
final otBaseProvider = Provider<List<OpsTask>>((ref) {
  final all = ref.watch(opsTasksFilteredListProvider);
  // In API mode `my_tasks=true` already narrowed this, and it sees more than the
  // local check can — the primary assignee FK *and* the M2M.
  if (ApiConfig.apiEnabled) return all;
  final mine = ref.watch(myTasksFProvider);
  return mine ? all.where((t) => t.isMine).toList() : all;
});

/// Count for a status tab within the base list — the fallback when the
/// server's counts are unavailable (mock mode, a failed call).
int otTabCount(List<OpsTask> base, String key) {
  if (key == 'all') return base.length;
  if (key == OpsTasksRemoteDataSource.overdueTab) return base.where(isTaskOverdue).length;
  return base.where((t) => opsTaskInTab(t, key)).length;
}

/// Whether a task belongs under a status tab.
///
/// The tab key is the org's own status name once
/// `/projects/project-task-statuses/` has loaded, and a built-in folded key
/// before it does or in mock mode. Both are accepted so the strip keeps working
/// through the switch-over, and so a task whose status was deleted still lands
/// somewhere via its folded key rather than vanishing.
bool opsTaskInTab(OpsTask t, String tabKey) =>
    t.statusName.trim().toLowerCase() == tabKey.trim().toLowerCase() ||
    t.status == tabKey;

/// Ops tasks under the selected tabs + search query. In API mode the server
/// already applied the tabs; "All" — with My Tasks on too — is every row the
/// server returned, finished ones included, as on the webapp.
final visibleOpsTasksProvider = Provider<List<OpsTask>>((ref) {
  final base = ref.watch(otBaseProvider);
  final tabs = ref.watch(otTabsProvider);
  final q = ref.watch(otSearchProvider).trim().toLowerCase();
  final projects = ref.watch(allProjectsProvider);

  Iterable<OpsTask> out = base;
  if (!ApiConfig.apiEnabled && tabs.isNotEmpty) {
    out = out.where((t) => tabs.any((k) => k == OpsTasksRemoteDataSource.overdueTab
        ? isTaskOverdue(t)
        : opsTaskInTab(t, k)));
  }
  if (q.isNotEmpty) {
    out = out.where((t) =>
        t.subject.toLowerCase().contains(q) ||
        t.id.toLowerCase().contains(q) ||
        opsTaskProjectName(t, projects).toLowerCase().contains(q) ||
        t.group.toLowerCase().contains(q));
  }
  return out.toList();
});

/// The project's name for a task row.
///
/// The row states it (`project_name`), so [all] is only consulted for mock rows,
/// which carry the id alone. Resolving from the loaded project list is not
/// enough on its own: a task can sit on a project that list never loaded.
String opsTaskProjectName(OpsTask t, List<Project> projects) {
  if (t.projectName.isNotEmpty) return t.projectName;
  return projects.where((p) => p.id == t.projId).map((p) => p.name).firstOrNull ?? '';
}

/// How many blockers a task is still waiting on.
///
/// Detail rows carry the dependency edges, so they can be resolved and filtered
/// to the ones still open. Slim list rows carry only the server's already-
/// pending count — which is why the badge never appeared in API mode.
int unresolvedDepCount(OpsTask t, List<OpsTask> all) =>
    t.waitingOn.isEmpty ? t.pendingDeps : unresolvedDeps(t, all).length;

/// Unresolved dependencies for a task (waiting-on tasks not yet done).
List<OpsTask> unresolvedDeps(OpsTask t, List<OpsTask> all) {
  return t.waitingOn
      .map((id) => all.where((x) => x.id == id).firstOrNull)
      .whereType<OpsTask>()
      .where((x) => x.status != 'completed' && x.status != 'cancelled')
      .toList();
}
