import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_endpoints.dart';
import 'server_search_providers.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../data/api/status_keys.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/crm_task.dart';
import 'crm_catalog_providers.dart';
import '../../domain/entities/view_schema.dart';
import '../../domain/repositories/crm_tasks_repository.dart';
import '../../infrastructure/data_sources/local/crm_tasks_mock_ds.dart';
import '../../infrastructure/data_sources/remote/crm_tasks_remote_ds.dart';
import '../../infrastructure/repositories/crm_tasks_api_repository.dart';
import '../../infrastructure/repositories/crm_tasks_repository_impl.dart';
import '../filters/tasks_filter_spec.dart';

/// DI seam: API-backed when a base URL is configured, mock seed otherwise.
final crmTasksRepositoryProvider = Provider<CrmTasksRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const CrmTasksRepositoryImpl(CrmTasksMockDataSource());
  }
  return CrmTasksApiRepository(
    CrmTasksRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Async source of all CRM tasks.
final crmTasksProvider = FutureProvider<List<CrmTask>>(
  (ref) => ref.watch(crmTasksRepositoryProvider).getTasks(),
);

/// The tasks linked to one lead — the Tasks tab on the lead detail screen.
/// Keyed by lead id: `GET /crm/tasks/?related_to=lead&related_to_id=<lead_id>
/// &is_followup=false`.
final leadTasksProvider =
    FutureProvider.family<List<CrmTask>, String>((ref, leadId) {
  if (leadId.isEmpty) return Future.value(const <CrmTask>[]);
  return ref.watch(crmTasksRepositoryProvider).getTasksForLead(leadId);
});

/// The org's Task **detail** layout, driving the "Task information" panel.
///
/// Fetched once per session — the layout changes when an admin edits it, not
/// when tasks change. Empty while in flight, in mock mode, and on failure, so
/// the panel renders its built-in rows rather than waiting.
final taskDetailSchemaFutureProvider = FutureProvider<ViewSchema>((ref) async {
  final repo = ref.watch(crmTasksRepositoryProvider);
  return repo.getTaskDetailSchema();
});

/// Synchronous view of [taskDetailSchemaFutureProvider].
final taskDetailSchemaProvider = Provider<ViewSchema>(
  (ref) => ref.watch(taskDetailSchemaFutureProvider).valueOrNull ?? ViewSchema.empty,
);

/// The org's Task layout for the mobile list card
/// (`?view_type=mobile`, falling back to `list`).
final taskListSchemaFutureProvider = FutureProvider<ViewSchema>(
  (ref) => ref.watch(crmTasksRepositoryProvider).getTaskListSchema(),
);

/// Synchronous view of [taskListSchemaFutureProvider] — empty while in flight,
/// so the list paints immediately with the built-in card and adopts the org's
/// column set when it arrives rather than waiting behind a spinner.
final taskListSchemaProvider = Provider<ViewSchema>(
  (ref) => ref.watch(taskListSchemaFutureProvider).valueOrNull ?? ViewSchema.empty,
);

/// The raw record row for one task — the values the schema-driven panel renders.
///
/// The mapped [CrmTask] cannot serve this: it drops `description`, `due_time`,
/// `duration`, `assigned_team` and `assignees`, all of which the org's detail
/// layout shows by default.
final taskRowProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) {
  if (id.isEmpty) return Future.value(null);
  return ref.watch(crmTasksRepositoryProvider).getTaskRow(id);
});

/// The raw record row for one **follow-up** — `GET /crm/tasks/{id}/?is_followup=true`.
///
/// A follow-up is a Task row, but the record endpoint only finds it under the
/// flag; [taskRowProvider] answers 404 for it, which left the follow-up detail
/// and edit form on list data (or "Could not load this task").
final followupRowProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) {
  if (id.isEmpty) return Future.value(null);
  return ref.watch(crmTasksRepositoryProvider).getTaskRow(id, isFollowup: true);
});

/// Look up a single task by id (used by the detail screen). Reads the merged
/// "all" set so session drafts and status overrides are reflected.
final crmTaskByIdProvider = Provider.family<CrmTask?, String>((ref, id) {
  final list = ref.watch(crmTasksAllProvider);
  for (final t in list) {
    if (t.id == id) return t;
  }
  return null;
});

// ── List UI state ──

/// Tasks added locally this session (from the Add task sheet). Prepended to the
/// repo-backed list so new records appear immediately.
final crmTaskDraftsProvider = StateProvider<List<CrmTask>>((ref) => const []);

/// Session-local status overrides for existing tasks, keyed by id → status.
/// Existing records come from a read-only [crmTasksProvider], so a status
/// change (e.g. → done) has nowhere else to persist; it is layered on here and
/// picked up by both the list and the detail via [crmTasksAllProvider].
final crmTaskStatusOverrideProvider =
    StateProvider<Map<String, String>>((ref) => const {});

// ── Server-side list query (webapp TasksListScreen) ──

/// Selected status chips (lane names) — multi-select, OR; empty is "All".
/// [crmTaskOtherChip] stands for "Other / no status".
final crmTaskChipsProvider = StateProvider<Set<String>>((ref) {
  ref.watch(apiServiceProvider); // reset per session
  return const {};
});
const crmTaskOtherChip = '__other__';

/// Webapp `toggleStatusChip`: "All" clears; statuses toggle; Other is
/// exclusive both ways.
Set<String> toggleCrmTaskChip(Set<String> current, String chip) {
  if (chip == 'all') return const {};
  if (chip == crmTaskOtherChip) return current.contains(chip) ? const {} : const {crmTaskOtherChip};
  final next = {...current}..remove(crmTaskOtherChip);
  if (!next.remove(chip)) next.add(chip);
  return next;
}

/// The drawer filters and search as the list endpoint's params — the chips
/// are applied on top, so counts follow search, filters and saved view.
final crmTaskServerQueryProvider = Provider<Map<String, dynamic>>((ref) {
  if (!ApiConfig.apiEnabled) return const {};
  final q = ref.watch(crmTaskSearchProvider).trim();
  return {
    ...ref.watch(taskFilterCodecProvider).encode(ref.watch(crmTaskFiltersProvider)),
    if (q.isNotEmpty) 'search': q,
  };
});

/// Rows for [crmTaskServerQueryProvider]; the unfiltered list when no
/// filter or search is set.
final crmTasksQueriedProvider = FutureProvider<List<CrmTask>>((ref) async {
  final query = ref.watch(crmTaskServerQueryProvider);
  if (query.isEmpty) return ref.watch(crmTasksProvider.future);
  // A write elsewhere (status tick, new task) refetches the base list; follow it.
  ref.watch(crmTasksProvider);
  return ref.watch(crmTasksRepositoryProvider).getTasksQuery(query);
});

/// [crmTasksQueriedProvider] with session drafts and status overrides laid on.
final crmTasksBaseProvider = Provider<List<CrmTask>>((ref) {
  final query = ref.watch(crmTaskServerQueryProvider);
  if (query.isEmpty) return ref.watch(crmTasksAllProvider);
  final repo = ref.watch(crmTasksQueriedProvider).valueOrNull ?? const [];
  final overrides = ref.watch(crmTaskStatusOverrideProvider);
  final catalog = ref.watch(taskStatusOptionsProvider);
  return [
    for (final t in repo)
      (overrides[t.id] != null && overrides[t.id] != t.status) ? _crmTaskWithStatus(t, overrides[t.id]!, catalog) : t,
  ];
});

/// Whether [t] sits in none of the org's lanes ("Other / no status").
bool crmTaskInNoLane(CrmTask t, List<CatalogOption> lanes) =>
    lanes.isNotEmpty && !lanes.any((l) => crmTaskInTab(t, l.name));

/// The full task set: session-added drafts first, then the repo-backed list,
/// with any session status overrides applied.
final crmTasksAllProvider = Provider<List<CrmTask>>((ref) {
  final repo = ref.watch(crmTasksProvider).valueOrNull ?? const [];
  final drafts = ref.watch(crmTaskDraftsProvider);
  final overrides = ref.watch(crmTaskStatusOverrideProvider);
  final merged = [...drafts, ...repo];
  if (overrides.isEmpty) return merged;
  // The org catalog is needed to move `statusName` along with the folded key —
  // without it an optimistically-ticked task would keep its old lane name and
  // so stay under its old tab.
  final catalog = ref.watch(taskStatusOptionsProvider);
  return [
    for (final t in merged)
      (overrides[t.id] != null && overrides[t.id] != t.status)
          ? _crmTaskWithStatus(t, overrides[t.id]!, catalog)
          : t,
  ];
});

/// Rebuilds a [CrmTask] with a new status (the entity has no `copyWith`).
///
/// [statusName] moves with it: the tabs match on the org's lane name, so
/// leaving the old name behind would file the task under the wrong tab until
/// the next refetch.
CrmTask _crmTaskWithStatus(
  CrmTask t,
  String status,
  List<CatalogOption> catalog,
) {
  var name = t.statusName;
  for (final s in catalog) {
    if (crmTaskStatusKey(name: s.name, type: s.statusType) == status) {
      name = s.name;
      break;
    }
  }
  return CrmTask(
    id: t.id,
    title: t.title,
    type: t.type,
    leadId: t.leadId,
    status: status,
    statusName: name,
    priority: t.priority,
    assignee: t.assignee,
    due: t.due,
    dueNote: t.dueNote,
  );
}

/// Active tab on the Tasks list (all / mine / overdue / status keys).
final crmTaskTabProvider = StateProvider<String>((ref) {
  ref.watch(apiServiceProvider); // reset per session
  return 'all';
});

/// Search query on the Tasks list.
final crmTaskSearchProvider = StateProvider<String>((ref) {
  ref.watch(apiServiceProvider); // reset per session
  return '';
});

/// Whether the search field is expanded.
final crmTaskSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Tasks filtered by the active tab + search query + drawer filters.
final visibleCrmTasksProvider = Provider<List<CrmTask>>((ref) {
  // Filters and search are applied server-side (API mode); mock mode keeps
  // filtering on the device.
  final server = ApiConfig.apiEnabled;
  final all = server ? ref.watch(crmTasksBaseProvider) : ref.watch(crmTasksAllProvider);
  final tab = ref.watch(crmTaskTabProvider);
  final chips = ref.watch(crmTaskChipsProvider);
  final q = ref.watch(crmTaskSearchProvider).trim().toLowerCase();
  final filters = ref.watch(crmTaskFiltersProvider);

  Iterable<CrmTask> out = all;
  if (tab == 'mine') {
    out = out.where((t) => t.isMine);
  } else if (tab == 'overdue') {
    out = out.where((t) => t.isOverdue);
  } else if (tab != 'all') {
    out = out.where((t) => crmTaskInTab(t, tab));
  }
  if (chips.contains(crmTaskOtherChip)) {
    final lanes = ref.watch(taskStatusOptionsProvider);
    out = out.where((t) => crmTaskInNoLane(t, lanes));
  } else if (chips.isNotEmpty) {
    out = out.where((t) => chips.any((c) => crmTaskInTab(t, c)));
  }
  if (server) return out.toList();
  if (!filters.isEmpty) out = out.where((t) => crmTaskMatchesFilters(t, filters));
  if (q.isNotEmpty) {
    // Same `?search=` the webapp sends: the server also matches description
    // and location, which the task rows do not carry.
    final matches = serverSearchMatcher(
      ref,
      ServerSearchKey(
        endpoint: ApiEndpoints.crmTasks,
        idFields: const ['task_id'],
        query: q,
        scope: const {'is_followup': 'false'},
      ),
    );
    out = out.where((t) => matches(
        [t.id], t.title.toLowerCase().contains(q) || t.id.toLowerCase().contains(q)));
  }
  return out.toList();
});

/// Whether a task belongs under a status tab.
///
/// The tab key is the org's own lane name once the catalog has loaded ("Open",
/// "Cancelled"), and a built-in folded key ("todo", "blocked") before it does
/// or in mock mode. Both are accepted so the screen keeps working through the
/// switch-over, and so a task whose lane was deleted still lands somewhere via
/// its folded key rather than vanishing.
bool crmTaskInTab(CrmTask t, String tabKey) =>
    t.statusName.trim().toLowerCase() == tabKey.trim().toLowerCase() ||
    t.status == tabKey;

/// Count of tasks for a given tab key.
int crmTaskTabCount(List<CrmTask> all, String key) {
  switch (key) {
    case 'all':
      return all.length;
    case 'mine':
      return all.where((t) => t.isMine).length;
    case 'overdue':
      return all.where((t) => t.isOverdue).length;
    default:
      return all.where((t) => crmTaskInTab(t, key)).length;
  }
}
