import 'package:intl/intl.dart';

import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/crm_task.dart';
import '../../../domain/entities/view_schema.dart';

/// Remote CRM tasks (`/crm/tasks/` with `is_followup=false`). HTTP + JSON →
/// [CrmTask] mapping only — caching lives in the API repository.
class CrmTasksRemoteDataSource {
  CrmTasksRemoteDataSource(this._api);

  final ApiService _api;

  /// Org task-status catalog, fetched once per data-source lifetime (it backs
  /// every status write and changes rarely).
  List<Map<String, dynamic>>? _statusCache;

  /// Raw list rows (followed up to 3 pages). The repository caches these.
  Future<List<Map<String, dynamic>>> fetchTaskRows() => _fetchRows();

  /// Raw rows for the tasks linked to one lead, scoped server-side with the
  /// shared generic-relation params rather than filtered after the fact.
  Future<List<Map<String, dynamic>>> fetchTaskRowsForLead(String leadId) =>
      fetchTaskRowsFor(relatedTo: 'lead', relatedToId: leadId);

  /// Raw rows for the tasks linked to **any** record — `related_to` is the
  /// lowercased model name (`lead`, `customer`).
  ///
  /// Generic because client-side filtering cannot do this job: the mapped
  /// [CrmTask] only carries `leadId`, populated when the relation happens to be
  /// a lead, so a customer's tasks are indistinguishable from unrelated ones in
  /// the org-wide list.
  Future<List<Map<String, dynamic>>> fetchTaskRowsFor({
    required String relatedTo,
    required String relatedToId,
  }) =>
      _fetchRows(relatedTo: relatedTo, relatedToId: relatedToId);

  Future<List<Map<String, dynamic>>> _fetchRows({
    String? relatedTo,
    String? relatedToId,
  }) async {
    final scoped = relatedTo != null && relatedToId != null;
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= 50; page++) {
      final body = await _api.get(ApiEndpoints.crmTasks, query: {
        'is_followup': 'false',
        // Trims each row to the org's **mobile** card config, which is where
        // the card's layout comes from. Verified on this resource: the default
        // payload has no `description`, so the column the org put on its card
        // had nothing to render.
        'view_type': 'mobile',
        'page_size': 100,
        // Both-or-neither by contract; one alone is a 400.
        if (scoped) 'related_to': relatedTo,
        if (scoped) 'related_to_id': relatedToId,
        if (page > 1) 'page': page,
      });
      final chunk = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      rows.addAll(chunk.results);
      if (chunk.next == null) break;
    }
    return rows;
  }

  /// The org's Task layout for the mobile list card.
  ///
  /// `mobile` is the view type meant for this screen — the org-view-settings
  /// engine documents it as "mobile list-row card", standalone from `list`
  /// (no `both` merge). Orgs seeded before that view type existed have no
  /// `mobile` rows, so fall back to `list` when it comes back with nothing.
  ///
  /// Caveat worth knowing: the **payload** is trimmed to the org's `list`
  /// config, because the data endpoints resolve their view type from the
  /// request action rather than a query param. A column visible on the card but
  /// hidden on the list therefore arrives with no value — which renders as
  /// absent, since the card skips empty values.
  Future<ViewSchema> fetchListSchema() async {
    final mobile = await _schema('mobile');
    return mobile.isNotEmpty ? mobile : _schema('list');
  }

  Future<ViewSchema> _schema(String viewType) async {
    try {
      final body = await _api.get(
        ApiEndpoints.crmTaskSchema,
        query: {'view_type': viewType},
      );
      return ViewSchema.fromResponse(body);
    } on Object {
      return ViewSchema.empty;
    }
  }

  /// The org's Task detail layout: `GET /crm/tasks/schema/?view_type=detail`.
  ///
  /// This is also what the record endpoint trims itself to, so layout and
  /// payload agree — a visible column with no value means the task has none.
  ///
  /// Best-effort: any failure yields the empty schema, which the panel reads as
  /// "use the built-in rows".
  Future<ViewSchema> fetchTaskDetailSchema() async {
    try {
      final body = await _api.get(
        ApiEndpoints.crmTaskSchema,
        query: {'view_type': 'detail'},
      );
      return ViewSchema.fromResponse(body);
    } on Object {
      return ViewSchema.empty;
    }
  }

  /// The raw record row for one task: `GET /crm/tasks/{id}/`.
  ///
  /// Returned **unmapped** on purpose. The detail panel renders whichever
  /// columns the org configured, so it needs values by field name — something
  /// the mapped [CrmTask] cannot answer, since it exposes a fixed set of
  /// properties and drops `description`, `due_time`, `duration`,
  /// `assigned_team` and `assignees` entirely.
  ///
  /// The record is also trimmed to the org's **detail** config, so it carries
  /// fields the list rows do not.
  Future<Map<String, dynamic>?> fetchTaskRow(String id) async {
    if (id.isEmpty) return null;
    final body = await _api.get(ApiEndpoints.crmTask(id));
    return body is Map<String, dynamic> ? body : null;
  }

  /// `PATCH /crm/tasks/{id}/` — saves an edit.
  ///
  /// [fields] is sent as-is: the caller built it from the org's own schema, so
  /// the key names are already the API's.
  Future<CrmTask?> updateTask(String id, Map<String, dynamic> fields) async {
    final body = await _api.patch(ApiEndpoints.crmTask(id), body: fields);
    if (body is! Map<String, dynamic>) return null;
    try {
      return taskFromJson(body);
    } on Object {
      return null;
    }
  }

  /// `DELETE /crm/tasks/{id}/`.
  Future<void> deleteTask(String id) => _api.delete(ApiEndpoints.crmTask(id));

  /// Mapped task list (malformed rows are skipped, never fatal).
  Future<List<CrmTask>> fetchTasks() async => mapRows(await fetchTaskRows());

  /// Mapped task list for one lead.
  Future<List<CrmTask>> fetchTasksForLead(String leadId) async =>
      mapRows(await fetchTaskRowsForLead(leadId));

  /// Creates a task; returns the mapped created row (null on shape surprise).
  /// Creates a task; returns the mapped created row (null on shape surprise).
  ///
  /// [fields] is sent **as given** apart from the normalising below, so a
  /// schema-driven form can post the org's whole field set — status, priority,
  /// duration, assignee, assignees — not just the handful this used to allow.
  /// It previously rebuilt the body from six known keys and dropped the rest,
  /// which silently discarded everything the built-in sheet did not collect.
  ///
  /// Verified against a live org: `status` writes as `status_id`, while
  /// `priority`, `assigned_to`, `assigned_team` and `assignees` all take their
  /// own names with bare uuids.
  Future<CrmTask?> createTask(Map<String, dynamic> fields) async {
    final body = <String, dynamic>{...fields};

    // `task_type` is required and has no server default.
    final type = _str(body['task_type'])?.trim();
    if (type == null || type.isEmpty) body['task_type'] = 'Task';

    // This endpoint serves tasks and follow-ups; without the flag a task can
    // be created as a follow-up and vanish from the Tasks list.
    body['is_followup'] ??= false;

    // The hand-written sheet supplies display forms ("24 Jun 2026", "10:00");
    // the schema form already supplies API forms. Both normalise to the same
    // thing here, and an unparseable value is dropped rather than rejected.
    if (body.containsKey('due_date')) {
      final iso = isoDateOrNull(_str(body['due_date']));
      iso == null ? body.remove('due_date') : body['due_date'] = iso;
    }
    if (body.containsKey('due_time')) {
      final time = apiTimeOrNull(_str(body['due_time']));
      time == null ? body.remove('due_time') : body['due_time'] = time;
    }

    final res = await _api.post(ApiEndpoints.crmTasks, body: body);
    return res is Map<String, dynamic> ? taskFromJson(res) : null;
  }

  /// The generic-relation pair, or nothing.
  ///
  /// `related_to` and `related_to_id` are **both-or-neither** by contract, so a
  /// half-populated pair is dropped rather than sent and rejected.
  static Map<String, dynamic> relatedTo(Map<String, dynamic> fields) {
    final model = _str(fields['related_to'])?.trim();
    final id = _str(fields['related_to_id'])?.trim();
    if (model == null || model.isEmpty || id == null || id.isEmpty) {
      return const {};
    }
    return {'related_to': model, 'related_to_id': id};
  }

  /// Sheet time text → the `HH:MM` the API accepts. Unparseable → null (field
  /// omitted on write rather than sent as junk).
  static String? apiTimeOrNull(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  /// Moves a task to the org status whose mapped UI key equals [uiStatusKey]
  /// (`todo | inprogress | blocked | done`). No matching status → no-op.
  Future<void> setTaskStatusByKey(String taskId, String uiStatusKey) async {
    final statusId = statusIdForKey(await statuses(), uiStatusKey);
    if (statusId == null) return;
    await _api.patch(ApiEndpoints.crmTask(taskId), body: {'status_id': statusId});
  }

  /// The org's task lanes as `name` → `status_type`, for folding.
  ///
  /// The list serializer sends `status` as a **display name with no
  /// `status_type`**, so without this the mapper can only guess from the name —
  /// and the guess is wrong for any lane whose name does not contain a keyword
  /// it looks for. "Cancelled" is the live example: it falls through to the
  /// `todo` default, so a cancelled task renders as an open one, unticked and
  /// counted as overdue.
  ///
  /// Best-effort: any failure yields an empty map, leaving the mapper on its
  /// name-matching path. Loading tasks must never fail because this did.
  Future<Map<String, String>> statusTypes() async {
    try {
      final out = <String, String>{};
      for (final row in await statuses()) {
        final name = _str(row['name'])?.trim().toLowerCase();
        final type = _str(row['status_type'])?.trim();
        if (name != null && name.isNotEmpty && type != null && type.isNotEmpty) {
          out[name] = type;
        }
      }
      return out;
    } on Object {
      return const {};
    }
  }

  /// The org's `crm-task-statuses` rows (cached in-memory after first fetch).
  Future<List<Map<String, dynamic>>> statuses() async {
    final cached = _statusCache;
    if (cached != null) return cached;
    final body =
        await _api.get(ApiEndpoints.crmTaskStatuses, query: {'page_size': 100});
    return _statusCache =
        Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
  }

  // ── mapping (static so tests + sibling data sources can reuse) ──

  static List<CrmTask> mapRows(List<Map<String, dynamic>> rows,
      {DateTime? now, Map<String, String> statusTypes = const {}}) {
    final out = <CrmTask>[];
    for (final row in rows) {
      final task = taskFromJson(row, now: now, statusTypes: statusTypes);
      if (task != null) out.add(task);
    }
    return out;
  }

  /// One list row → [CrmTask]. Defensive on every field; a row without a
  /// `task_id` returns null (caller skips it).
  static CrmTask? taskFromJson(Map<String, dynamic> json,
      {DateTime? now, Map<String, String> statusTypes = const {}}) {
    final id = _str(json['task_id']);
    if (id == null || id.isEmpty) return null;

    final related = json['related_to'];
    final relatedMap = related is Map ? related : null;
    final assigned = json['assigned_to'];
    UserDirectory.registerJson(assigned);
    final priority = json['priority'];
    final statusRaw = json['status'];
    final statusLabel =
        (statusRaw is Map ? _str(statusRaw['name']) : _str(statusRaw)) ?? '';
    final due = parseApiDate(json['due_date']);

    return CrmTask(
      raw: json,
      id: id,
      title: _str(json['title']) ?? '',
      description: _str(json['description'])?.trim() ?? '',
      type: _str(json['task_type']) ?? '',
      leadId: relatedMap?['model'] == 'lead' ? _str(relatedMap?['id']) : null,
      status: crmTaskStatusKey(
        name: statusLabel,
        // The row carries no `status_type`, so the catalog supplies it. Without
        // it "Cancelled" folds to the `todo` default and a cancelled task reads
        // as an open one.
        type: statusTypes[statusLabel.toLowerCase()] ??
            (statusRaw is Map ? _str(statusRaw['status_type']) : null),
      ),
      // Kept verbatim beside the folded key so the tabs and the card pill can
      // show the org's own lane name (see [CrmTask.statusName]).
      statusName: statusLabel,
      priority: priorityKey(priority is Map ? _str(priority['name']) : null),
      assignee: UserDirectory.mapUserId(
          assigned is Map ? _str(assigned['user_id']) : null),
      due: absoluteDate(due),
      dueNote: dueNoteFor(due, now: now),
    );
  }

  /// "2d overdue" / "Today" / "In 3d" / "" — computed from the due date only
  /// (the UI's `isOverdue` already excludes done tasks).
  static String dueNoteFor(DateTime? due, {DateTime? now}) {
    if (due == null) return '';
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final day = DateTime(due.year, due.month, due.day);
    final days = day.difference(today).inDays;
    if (days < 0) return '${-days}d overdue';
    if (days == 0) return 'Today';
    if (days <= 7) return 'In ${days}d';
    return '';
  }

  /// The `crm_task_status_id` whose name/type maps onto [uiStatusKey], or null.
  static String? statusIdForKey(
      List<Map<String, dynamic>> statuses, String uiStatusKey) {
    for (final s in statuses) {
      final key = crmTaskStatusKey(
          name: _str(s['name']), type: _str(s['status_type']));
      if (key == uiStatusKey) return _str(s['crm_task_status_id']);
    }
    return null;
  }

  /// Sheet date text → `YYYY-MM-DD`, accepting ISO ("2026-06-24") and the UI's
  /// "24 Jun 2026" display format. Unparseable → null (field omitted on write).
  static String? isoDateOrNull(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    DateTime? d = DateTime.tryParse(s);
    if (d == null) {
      try {
        d = DateFormat('d MMM yyyy').parseStrict(s);
      } on FormatException {
        d = null;
      }
    }
    return d == null ? null : DateFormat('yyyy-MM-dd').format(d);
  }
}

String? _str(Object? v) => v is String ? v : null;
