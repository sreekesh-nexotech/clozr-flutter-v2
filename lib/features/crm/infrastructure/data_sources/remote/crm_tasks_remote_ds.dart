import 'package:intl/intl.dart';

import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/crm_task.dart';

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
      _fetchRows(leadId: leadId);

  Future<List<Map<String, dynamic>>> _fetchRows({String? leadId}) async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= 50; page++) {
      final body = await _api.get(ApiEndpoints.crmTasks, query: {
        'is_followup': 'false',
        'page_size': 100,
        if (leadId != null) 'related_to': 'lead',
        if (leadId != null) 'related_to_id': leadId,
        if (page > 1) 'page': page,
      });
      final chunk = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      rows.addAll(chunk.results);
      if (chunk.next == null) break;
    }
    return rows;
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

  /// Mapped task list (malformed rows are skipped, never fatal).
  Future<List<CrmTask>> fetchTasks() async => mapRows(await fetchTaskRows());

  /// Mapped task list for one lead.
  Future<List<CrmTask>> fetchTasksForLead(String leadId) async =>
      mapRows(await fetchTaskRowsForLead(leadId));

  /// Creates a task; returns the mapped created row (null on shape surprise).
  Future<CrmTask?> createTask(Map<String, dynamic> fields) async {
    final body = <String, dynamic>{
      'title': _str(fields['title'])?.trim() ?? '',
      'task_type': _str(fields['task_type']) ?? 'Task',
      'is_followup': false,
    };
    final desc = _str(fields['description'])?.trim();
    if (desc != null && desc.isNotEmpty) body['description'] = desc;
    final iso = isoDateOrNull(_str(fields['due_date']));
    if (iso != null) body['due_date'] = iso;
    final time = apiTimeOrNull(_str(fields['due_time']));
    if (time != null) body['due_time'] = time;
    body.addAll(relatedTo(fields));
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
      {DateTime? now}) {
    final out = <CrmTask>[];
    for (final row in rows) {
      final task = taskFromJson(row, now: now);
      if (task != null) out.add(task);
    }
    return out;
  }

  /// One list row → [CrmTask]. Defensive on every field; a row without a
  /// `task_id` returns null (caller skips it).
  static CrmTask? taskFromJson(Map<String, dynamic> json, {DateTime? now}) {
    final id = _str(json['task_id']);
    if (id == null || id.isEmpty) return null;

    final related = json['related_to'];
    final relatedMap = related is Map ? related : null;
    final assigned = json['assigned_to'];
    UserDirectory.registerJson(assigned);
    final priority = json['priority'];
    final statusRaw = json['status'];
    final due = parseApiDate(json['due_date']);

    return CrmTask(
      id: id,
      title: _str(json['title']) ?? '',
      type: _str(json['task_type']) ?? '',
      leadId: relatedMap?['model'] == 'lead' ? _str(relatedMap?['id']) : null,
      status: crmTaskStatusKey(
        name: statusRaw is Map ? _str(statusRaw['name']) : _str(statusRaw),
      ),
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
