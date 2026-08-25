import 'package:intl/intl.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../crm/domain/entities/audit_entry.dart';
import '../../../../crm/domain/entities/crm_catalog.dart';
// `hexColor` — the shared `#RRGGBB` parser every org catalog colours through.
import '../../../../crm/infrastructure/data_sources/remote/crm_catalog_remote_ds.dart'
    show hexColor;
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/ops_task.dart';

/// Remote source for Operations (PMO) tasks: HTTP + JSON→entity mapping only.
///
/// List reads use the fixed `?view=list` 19-field slim projection
/// (operations-task.md §1). Slim rows carry no `exp_start_date`, subtask
/// rows, dependency edges, notes, department, colour tag or time
/// bookkeeping, so those entity fields fall back to safe defaults.
class OpsTasksRemoteDataSource {
  const OpsTasksRemoteDataSource(this._api);

  final ApiService _api;

  static const int _pageSize = 100;
  static const int _maxPages = 50; // safety cap; loop still breaks when next == null

  /// Neutral colour tag for API rows — same `OpsColorTag(name, hex)` shape the
  /// mock seed uses, with an empty name and the grey token.
  static const OpsColorTag neutralTag = OpsColorTag('', AppColors.textMuted);

  /// All PMO tasks visible to the caller — slim rows, up to 3 pages of 100.
  /// The org's project-task statuses (`operations.md` §13.4) — the tab strip and
  /// the drawer's Status facet.
  ///
  /// Note the path: `project-task-statuses/`, not `/projects/task-statuses/`
  /// (404s) and not `/crm/crm-task-statuses/` (the separate CRM-task set) — the
  /// doc calls both out explicitly.
  ///
  /// Best-effort; a failure yields the empty list, which callers read as "no
  /// catalog, use the built-in vocabulary".
  Future<List<CatalogOption>> fetchOpsTaskStatuses() async {
    try {
      final body = await _api
          .get(ApiEndpoints.projectTaskStatuses, query: {'page_size': 100});
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      final out = <CatalogOption>[];
      for (final row in rows) {
        if (row['is_active'] == false) continue;
        final id = (row['project_task_status_id'] ?? '').toString();
        // `operations.md` §13.4 names the label field `status`, the task doc's
        // rows call it `name`. Accept both rather than betting on one.
        final name = (row['name'] ?? row['status'] ?? '').toString();
        if (id.isEmpty || name.isEmpty) continue;
        out.add(CatalogOption(
          id: id,
          name: name,
          // Carried through so the subtask tick can resolve its target status
          // without folding the org's own names.
          isClosed: row['is_closed'] == true,
          isCancelled: row['is_cancelled'] == true,
        ));
      }
      return out;
    } on Object {
      return const [];
    }
  }

  /// The lanes on one project (`operations.md` §12.1) — `{task_group_id,
  /// title}`, ordered by `position`.
  ///
  /// Groups are per-project, so this takes the project id; an empty id means
  /// no project is picked yet and there is nothing to ask for.
  ///
  /// Best-effort like the status catalog: a failure yields the empty list, and
  /// the picker then offers "No group" alone rather than inventing lanes.
  Future<List<CatalogOption>> fetchTaskGroups(String projectId) async {
    if (projectId.isEmpty) return const [];
    try {
      final body = await _api.get(ApiEndpoints.taskGroups,
          query: {'project': projectId, 'page_size': 100});
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      final out = <CatalogOption>[];
      for (final row in rows) {
        final id = (row['task_group_id'] ?? '').toString();
        final title = (row['title'] ?? '').toString();
        if (id.isEmpty || title.isEmpty) continue;
        out.add(CatalogOption(id: id, name: title));
      }
      return out;
    } on Object {
      return const [];
    }
  }

  /// Per-status tab counts (`operations-task.md` §2), under the same [filters]
  /// as the list. The server strips the status facet itself, so selecting a tab
  /// never zeroes the others.
  ///
  /// Note the name key: this response labels each status `status`, where the
  /// projects aggregate uses `name`.
  ///
  /// Returns `('all' → total, '<status name>' → count)`. Best-effort: a failure
  /// yields an empty map, which the caller reads as "count locally".
  Future<Map<String, int>> fetchStatusCounts(Map<String, dynamic> filters) async {
    try {
      final body = await _api.get(ApiEndpoints.projectTaskStatusCounts, query: {
        // Paging and the status facet are meaningless here; the server ignores
        // the latter anyway, but sending it invites confusion.
        ...{...filters}..removeWhere((k, _) =>
            k == 'page' ||
            k == 'page_size' ||
            k == 'status' ||
            k.startsWith('status__') ||
            k.startsWith('status_name')),
      });
      if (body is! Map) return const {};
      final out = <String, int>{'all': _int(body['total'])};
      for (final row in (body['statuses'] as List? ?? const [])) {
        if (row is! Map) continue;
        final name = (row['status'] ?? '').toString();
        if (name.isEmpty) continue;
        out[name] = _int(row['count']);
      }
      return out;
    } on Object {
      return const {};
    }
  }

  /// [filters] are `/projects/tasks/` query params from the drawer, the status
  /// tabs and the My-tasks toggle — applied **server-side**.
  Future<List<OpsTask>> fetchOpsTasks({Map<String, dynamic> filters = const {}}) async {
    final out = <OpsTask>[];
    for (var page = 1; page <= _maxPages; page++) {
      final body = await _api.get(ApiEndpoints.projectTasks, query: {
        // Paging steers the walk itself, so a stored filter can never own it.
        ...{...filters}..removeWhere((k, _) => k == 'page' || k == 'page_size'),
        'view': 'list',
        'page_size': _pageSize,
        if (page > 1) 'page': page,
      });
      final paged = Paginated.fromAny<OpsTask?>(body, mapOpsTask);
      out.addAll(paged.results.whereType<OpsTask>());
      if (!paged.hasMore) break;
    }
    return out;
  }

  /// One task in its **full shape** (`operations-task.md` §3) — the
  /// description, expected start, department and dependency edges that the
  /// `?view=list` projection drops.
  ///
  /// The edit form prefilled from a list row, so those fields came up blank
  /// regardless of what was stored.
  Future<OpsTask?> fetchOpsTask(String id) async {
    if (id.isEmpty) return null;
    final body = await _api.get(ApiEndpoints.projectTask(id));
    return body is Map<String, dynamic> ? mapOpsTask(body) : null;
  }

  /// `POST /projects/tasks/` with the non-empty subset of [fields]. Returns
  /// the created task mapped through [mapOpsTask] (null when the response row
  /// is unusable — callers treat that as "refetch the list").
  Future<OpsTask?> createOpsTask(Map<String, dynamic> fields) async {
    final body = await _api.post(ApiEndpoints.projectTasks, body: _clean(fields));
    return body is Map<String, dynamic> ? mapOpsTask(body) : null;
  }

  /// `PATCH /projects/tasks/{id}/` with the non-empty subset of [fields].
  Future<void> updateOpsTask(String id, Map<String, dynamic> fields) =>
      _api.patch(ApiEndpoints.projectTask(id), body: _clean(fields));

  /// `DELETE /projects/tasks/{id}/` → `204`, or `409` when another task depends
  /// on this one. Errors are not swallowed: only the blocker side is protected,
  /// so the refusal is actionable.
  Future<void> deleteOpsTask(String id) => _api.delete(ApiEndpoints.projectTask(id));

  /// Adds a "waiting on" edge (§3D).
  ///
  /// Errors are deliberately not swallowed: self-dependency, a duplicate edge,
  /// a cross-project blocker and cycle detection all come back as field-keyed
  /// `400`s, and each one is the only explanation the user would get.
  Future<void> addDependency({required String taskId, required String dependsOn}) =>
      _api.post(ApiEndpoints.taskDependencies,
          body: {'task': taskId, 'depends_on': dependsOn});

  /// Removes an edge by its own id — not the blocker's task id.
  Future<void> removeDependency(String edgeId) =>
      _api.delete(ApiEndpoints.taskDependency(edgeId));

  // ── subtasks (§3C) ──

  /// One task's direct subtasks — `GET /projects/tasks/?parent=<task_id>`.
  ///
  /// A subtask is an ordinary task with `parent_task` set, so these are the
  /// same slim rows the list uses; only the checklist fields are kept.
  ///
  /// [closedStatusIds] are the org's closed statuses, which is what decides
  /// whether a row is ticked. Falling back to folding the status *name* would
  /// call an org's "Archived" lane open.
  ///
  /// One page: a checklist past 100 items is not a checklist, and the parent's
  /// own `subtask_count` is what the counter falls back to anyway.
  Future<List<Subtask>> fetchSubtasks(
    String parentId, {
    Set<String> closedStatusIds = const {},
  }) async {
    if (parentId.isEmpty) return const [];
    final body = await _api.get(ApiEndpoints.projectTasks, query: {
      'parent': parentId,
      'view': 'list',
      'page_size': _pageSize,
    });
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    final out = <Subtask>[];
    for (final row in rows) {
      final t = mapOpsTask(row);
      if (t == null) continue;
      final statusId = (row['status'] ?? '').toString();
      out.add(Subtask(
        id: t.id,
        title: t.subject,
        done: closedStatusIds.isNotEmpty
            ? closedStatusIds.contains(statusId)
            : t.status == 'completed' || t.status == 'cancelled',
        who: t.assignees.isEmpty ? '' : t.assignees.first,
        due: t.end,
      ));
    }
    return out;
  }

  /// Adds a subtask — `POST /projects/tasks/` with `parent_task` set (§3C).
  ///
  /// `bulk-create` rejects rows carrying `parent_task`, so subtasks are created
  /// one at a time whatever the caller does.
  Future<void> createSubtask({
    required String parentId,
    required String subject,
    String projectId = '',
  }) =>
      _api.post(ApiEndpoints.projectTasks, body: _clean({
        'parent_task': parentId,
        'subject': subject,
        if (projectId.isNotEmpty) 'project': projectId,
      }));

  // ── activity (§3B) ──

  /// One task's own audit trail — `GET /projects/tasks/{id}/activity/`.
  ///
  /// Rows arrive **pre-humanized** (`summary` + `event_type`), unlike the
  /// org-wide `/access-control/audit-logs/` feed the CRM screens read, so there
  /// is no diff to interpret here — the summary is the sentence.
  ///
  /// [statusNames] maps `project_task_status_id` → the org's name for it. The
  /// server humanizes the summary but does **not** resolve the status FK, so a
  /// status move arrives as the literal
  /// `"Status changed to 7803f448-03a7-4a77-8bf0-5918f50655b5"` — a raw UUID in
  /// the user's timeline unless it is substituted here.
  ///
  /// Best-effort: any failure yields the empty list and the card simply does
  /// not render. Inventing a timeline would be worse than showing none.
  Future<List<AuditEntry>> fetchTaskActivity(
    String taskId, {
    Map<String, String> statusNames = const {},
  }) async {
    if (taskId.isEmpty) return const [];
    try {
      final body = await _api.get(ApiEndpoints.projectTaskActivity(taskId),
          query: {'page_size': 30});
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      final out = <AuditEntry>[];
      for (var i = 0; i < rows.length; i++) {
        final entry = mapActivity(rows[i], i, statusNames: statusNames);
        if (entry != null) out.add(entry);
      }
      return out;
    } on Object {
      return const [];
    }
  }

  /// One activity row → a timeline entry, or null when it carries no summary
  /// worth showing. Visible for tests.
  ///
  /// [index] is the fallback id for a row with no `audit_log_id`; entries are
  /// only ever identified within one fetched list.
  static AuditEntry? mapActivity(
    Map<String, dynamic> row,
    int index, {
    Map<String, String> statusNames = const {},
  }) {
    final summary = _resolveIds(
      (row['summary'] ?? '').toString().trim(),
      statusNames,
    );
    if (summary.isEmpty) return null;
    return AuditEntry(
      id: (row['audit_log_id'] ?? '$index').toString(),
      kind: _activityKind(
        (row['event_type'] ?? '').toString(),
        (row['action'] ?? '').toString(),
        summary,
      ),
      title: summary,
      // The summary is the whole sentence; the actor and the time are appended
      // by the card, so a subtitle here would only repeat it.
      subtitle: '',
      at: parseApiDate(row['timestamp']),
      actor: (row['user_full_name'] ?? '').toString(),
    );
  }

  /// Substitutes any uuid in [summary] with the org's name for it.
  ///
  /// The server writes "Status changed to <uuid>"; only the status catalog can
  /// turn that into "Status changed to Completed". A uuid with no match is left
  /// as it is — wrong-but-honest beats dropping the entry.
  static String _resolveIds(String summary, Map<String, String> names) {
    if (summary.isEmpty || names.isEmpty) return summary;
    return summary.replaceAllMapped(
      RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
          r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'),
      (m) => names[m[0]] ?? m[0]!,
    );
  }

  /// `event_type` → the icon the timeline row uses. The enum is
  /// `created | updated | field_changed | deleted | child_created |
  /// child_updated | child_deleted`; a status move is only distinguishable by
  /// its summary, which the server writes as "Status changed to …".
  static AuditEventKind _activityKind(String eventType, String action, String summary) {
    if (summary.toLowerCase().startsWith('status changed')) {
      return AuditEventKind.statusChanged;
    }
    return switch (eventType.isNotEmpty ? eventType : action) {
      'created' || 'create' => AuditEventKind.created,
      'deleted' || 'delete' || 'child_deleted' => AuditEventKind.deleted,
      'child_created' => AuditEventKind.childAdded,
      'updated' || 'field_changed' || 'child_updated' => AuditEventKind.fieldChanged,
      _ => AuditEventKind.other,
    };
  }

  // ── mapping ──

  /// `?view=list` slim row (or a full row — create/detail responses share the
  /// field names) → [OpsTask]. Returns null for rows without a `task_id`;
  /// every other field degrades to a safe default instead of throwing.
  ///
  /// `projId` is the `project` UUID, matching `Project.id` (which is always
  /// the `project_id` UUID) so cross-references resolve.
  ///
  /// Known slim-row limitation: the API exposes only
  /// `pending_dependency_count`, not the dependency edges, so `waitingOn` stays
  /// empty. The count lands in `pendingDeps` instead, which is what the list's
  /// "Waiting on N" badge reads — the edges themselves only matter on detail,
  /// where the full row carries them.
  static OpsTask? mapOpsTask(Map<String, dynamic> row) {
    final id = row['task_id'] as String? ?? '';
    if (id.isEmpty) return null;

    UserDirectory.registerJson(row['assigned_to']);
    final assignees = <String>[];
    final rawAssignees = row['assignees'];
    if (rawAssignees is List) {
      for (final a in rawAssignees) {
        if (a is Map) {
          UserDirectory.registerJson(a);
          final mapped = UserDirectory.mapUserId(a['user_id'] as String?);
          if (mapped.isNotEmpty) assignees.add(mapped);
        }
      }
    }

    final endRaw = row['exp_end_date'] as String? ?? '';
    final endDate = parseApiDate(endRaw);
    // Detail-only: absent on `?view=list` rows, which leaves the start blank
    // rather than inventing one.
    final startRaw = row['exp_start_date'] as String? ?? '';
    final startDate = parseApiDate(startRaw);

    // When the work actually happened, as opposed to when it was planned to.
    // Never read before, which left the detail page's "Actual: started … ·
    // completed …" row showing "—" on every task the org had finished, and the
    // completed-tasks grid with no way to tell early from late.
    final actualStartRaw = row['act_start_date'] as String? ?? '';
    // `completed_on` is stamped when the status moves to a closed one;
    // `act_end_date` is the date a user can set by hand. Either answers "when
    // was this finished", so the explicit one wins and the stamp backs it up.
    final actualEndRaw = (row['act_end_date'] as String? ?? '').isNotEmpty
        ? row['act_end_date'] as String
        : (row['completed_on'] as String? ?? '');
    final actualStartDate = parseApiDate(actualStartRaw);
    final actualEndDate = parseApiDate(actualEndRaw);

    // Detail-only and already labelled: `dependencies` are the tasks this one
    // waits on, `dependents` the ones waiting on it. Both carry the other
    // task's subject and status, so no chip needs a second lookup.
    final deps = _edges(row['dependencies']);
    final blocking = _edges(row['dependents']);
    final waitingOn = [for (final d in deps) d.taskId];

    return OpsTask(
      id: id,
      subject: row['subject'] as String? ?? '',
      projId: row['project'] as String? ?? '',
      projectName: (row['project_name'] as String? ?? '').trim(),
      groupId: (row['task_group'] as String? ?? '').trim(),
      typeId: (row['type'] as String? ?? '').trim(),
      typeName: (row['task_type_name'] as String? ?? '').trim(),
      deps: deps,
      blocking: blocking,
      code: (row['task_code'] as String? ?? '').trim(),
      subtaskCount: _int(row['subtask_count']),
      subtaskDoneCount: _int(row['subtask_done_count']),
      pendingDeps: _int(row['pending_dependency_count']),
      isOverdue: row['is_overdue'] is bool ? row['is_overdue'] as bool : null,
      group: row['task_group_name'] as String? ?? 'No group',
      status: opsTaskStatusKey(name: row['status_name'] as String?),
      statusName: (row['status_name'] as String? ?? '').trim(),
      pri: priorityKey(row['priority'] as String?),
      assignees: assignees,
      milestone: row['is_milestone'] == true,
      start: absoluteDate(startDate),
      startTime: _timeOf(startRaw, startDate),
      end: absoluteDate(endDate),
      endTime: _timeOf(endRaw, endDate),
      endISO: endRaw,
      // Detail-only decimals. Hardcoded 0 and 1 before, so the detail page
      // printed "0 hrs" / "1" on every task whatever the org had stored — and
      // the edit form then wrote that back. Null (not 0) on a slim row, which
      // is what keeps the rows hidden until the retrieve answers.
      expHrs: _decimal(row['expected_time']),
      weight: _decimal(row['task_weight']),
      progress: _progress(row),
      // Free text on the full object — there is no Department model, so no
      // lookup endpoint and no id to resolve.
      dept: (row['department'] as String? ?? '').trim(),
      // The org's own swatch (`"#E74C3C"`), detail-only. Every API task used to
      // come back grey because this was pinned to [neutralTag].
      color: _colorTag(row['color']),
      subtasks: const [], // slim rows expose subtask_count only
      waitingOn: waitingOn, // detail only; see the note above
      notes: const [],
      desc: row['description'] as String? ?? '',
      actualStart: actualStartDate == null ? null : absoluteDate(actualStartDate),
      actualEnd: actualEndDate == null ? null : absoluteDate(actualEndDate),
      actualEndFull: actualEndDate == null
          ? null
          : '${absoluteDate(actualEndDate)}, ${_timeOf(actualEndRaw, actualEndDate)}',
      actualEndISO: actualEndRaw.isEmpty ? null : actualEndRaw,
    );
  }

  /// A `dependencies` / `dependents` array → labelled edges. Rows without the
  /// other task's id are dropped: a chip that cannot be opened is not useful.
  static List<TaskDep> _edges(Object? raw) {
    if (raw is! List) return const [];
    final out = <TaskDep>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final taskId = (e['task_id'] ?? '').toString();
      if (taskId.isEmpty) continue;
      out.add(TaskDep(
        edgeId: (e['task_depends_on_id'] ?? '').toString(),
        taskId: taskId,
        subject: (e['subject'] ?? '').toString(),
        statusName: (e['status_name'] ?? '').toString(),
        isClosed: e['is_closed'] == true,
      ));
    }
    return out;
  }

  /// A decimal field ("24.000000") → its number, or null when the row does not
  /// carry the key at all. Null and 0 mean different things here: "the slim
  /// projection dropped it" versus "the org stored nothing".
  static double? _decimal(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  /// The colour tag. Keeps the raw string as the name — it is free-form, so an
  /// org may store a label rather than a hex — and falls back to the grey token
  /// when it is not a colour this app can draw.
  static OpsColorTag _colorTag(Object? v) {
    final raw = (v ?? '').toString().trim();
    if (raw.isEmpty) return neutralTag;
    return OpsColorTag(raw, hexColor(raw) ?? neutralTag.hex);
  }

  /// Counts arrive as JSON numbers, but tolerate a string just in case.
  static int _int(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  /// Prefer the server's subtask rollup (`computed_progress`, a JSON number);
  /// fall back to the task's own `progress` decimal string. Always returns an
  /// int so the entity never re-derives from the (empty) local subtask list.
  static int _progress(Map<String, dynamic> row) {
    final computed = row['computed_progress'];
    if (computed is num) return computed.round().clamp(0, 100).toInt();
    return parseAmount(row['progress']).round().clamp(0, 100).toInt();
  }

  /// The time part of `exp_end_date` — present on datetime values
  /// ("2026-06-28T17:00:00Z"), absent on bare dates ("2026-06-28").
  static String _timeOf(String raw, DateTime? parsed) {
    if (parsed == null || !raw.contains('T')) return '';
    return DateFormat('h:mm a').format(parsed.toLocal());
  }

  /// Drops null / empty-string values so POST/PATCH bodies only carry real
  /// user input.
  static Map<String, dynamic> _clean(Map<String, dynamic> fields) => {
        for (final e in fields.entries)
          if (e.value != null && (e.value is! String || (e.value as String).isNotEmpty)) e.key: e.value,
      };
}
