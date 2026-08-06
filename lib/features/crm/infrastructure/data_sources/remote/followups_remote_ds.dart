import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/followup.dart';
import 'crm_tasks_remote_ds.dart';

/// Remote follow-ups — the same `/crm/tasks/` resource scoped with
/// `is_followup=true`. HTTP + JSON → [Followup] mapping only.
class FollowupsRemoteDataSource {
  FollowupsRemoteDataSource(this._api);

  final ApiService _api;

  List<Map<String, dynamic>>? _statusCache;

  /// Raw list rows (followed up to 3 pages). The repository caches these.
  Future<List<Map<String, dynamic>>> fetchFollowupRows() => _fetchRows();

  /// Raw rows for the follow-ups linked to one lead, scoped server-side with
  /// the shared generic-relation params rather than filtered after the fact.
  Future<List<Map<String, dynamic>>> fetchFollowupRowsForLead(String leadId) =>
      _fetchRows(leadId: leadId);

  Future<List<Map<String, dynamic>>> _fetchRows({String? leadId}) async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= 50; page++) {
      final body = await _api.get(ApiEndpoints.crmTasks, query: {
        'is_followup': 'true',
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

  /// Mapped follow-up list (malformed rows are skipped, never fatal).
  Future<List<Followup>> fetchFollowups() async =>
      mapRows(await fetchFollowupRows());

  /// Mapped follow-up list for one lead.
  Future<List<Followup>> fetchFollowupsForLead(String leadId) async =>
      mapRows(await fetchFollowupRowsForLead(leadId));

  /// Creates a follow-up; returns the mapped created row (null on shape
  /// surprise). `task_type` must be an org follow-up type name.
  Future<Followup?> createFollowup(Map<String, dynamic> fields) async {
    final body = <String, dynamic>{
      'title': _str(fields['title'])?.trim() ?? '',
      'task_type': _str(fields['task_type']) ?? 'Call',
      'is_followup': true,
    };
    final desc = _str(fields['description'])?.trim();
    if (desc != null && desc.isNotEmpty) body['description'] = desc;
    final iso = CrmTasksRemoteDataSource.isoDateOrNull(_str(fields['due_date']));
    if (iso != null) body['due_date'] = iso;
    final time = CrmTasksRemoteDataSource.apiTimeOrNull(_str(fields['due_time']));
    if (time != null) body['due_time'] = time;
    body.addAll(CrmTasksRemoteDataSource.relatedTo(fields));
    final res = await _api.post(ApiEndpoints.crmTasks, body: body);
    return res is Map<String, dynamic> ? followupFromJson(res) : null;
  }

  /// Marks a follow-up done (→ the org's completed-type status) or reopens it
  /// (→ the default / first open-type status). No usable status → no-op.
  Future<void> setFollowupDone(String id, bool done) async {
    final statuses = await _statuses();
    final statusId = done
        ? CrmTasksRemoteDataSource.statusIdForKey(statuses, 'done')
        : openStatusId(statuses);
    if (statusId == null) return;
    await _api.patch(ApiEndpoints.crmTask(id), body: {'status_id': statusId});
  }

  Future<List<Map<String, dynamic>>> _statuses() async {
    final cached = _statusCache;
    if (cached != null) return cached;
    final body =
        await _api.get(ApiEndpoints.crmTaskStatuses, query: {'page_size': 100});
    return _statusCache =
        Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
  }

  // ── mapping (static so tests + the API repository can reuse) ──

  static List<Followup> mapRows(List<Map<String, dynamic>> rows,
      {DateTime? now}) {
    final out = <Followup>[];
    for (final row in rows) {
      final fu = followupFromJson(row, now: now);
      if (fu != null) out.add(fu);
    }
    return out;
  }

  /// One list row → [Followup]. Defensive on every field; a row without a
  /// `task_id` returns null (caller skips it).
  static Followup? followupFromJson(Map<String, dynamic> json, {DateTime? now}) {
    final id = _str(json['task_id']);
    if (id == null || id.isEmpty) return null;

    final title = _str(json['title']) ?? '';
    final related = json['related_to'];
    final relatedMap = related is Map ? related : null;
    final relatedModel = _str(relatedMap?['model']);
    final relatedId = _str(relatedMap?['id']);
    final label = _str(relatedMap?['label']);
    final assigned = json['assigned_to'];
    UserDirectory.registerJson(assigned);
    final statusRaw = json['status'];
    final statusName =
        statusRaw is Map ? _str(statusRaw['name']) : _str(statusRaw);
    final dueDate = parseApiDate(json['due_date']);
    final desc = _str(json['description'])?.trim();

    return Followup(
      id: id,
      kind: _str(json['task_type']) ?? '',
      contact: label ?? title,
      custId: relatedModel == 'customer' ? relatedId : null,
      leadId: relatedModel == 'lead' ? relatedId : null,
      company: label ?? '',
      due: absoluteDate(dueDate),
      time: trimTime(json['due_time']),
      status: followupStatusKey(
        isCompleted: crmTaskStatusKey(name: statusName) == 'done',
        dueDate: dueDate,
        now: now,
      ),
      owner: UserDirectory.mapUserId(
          assigned is Map ? _str(assigned['user_id']) : null),
      agenda: (desc != null && desc.isNotEmpty) ? desc : title,
    );
  }

  /// `"11:00:00"` → `"11:00"`; null/junk → `''`.
  static String trimTime(Object? value) {
    final s = _str(value)?.trim() ?? '';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  /// The status to reopen into: the default open-type status, else the first
  /// open-type one, else the first status that doesn't map to `done`.
  static String? openStatusId(List<Map<String, dynamic>> statuses) {
    Map<String, dynamic>? fallback;
    for (final s in statuses) {
      if (_str(s['status_type']) == 'open') {
        if (s['is_default'] == true) return _str(s['crm_task_status_id']);
        fallback ??= s;
      }
    }
    if (fallback != null) return _str(fallback['crm_task_status_id']);
    for (final s in statuses) {
      final key = crmTaskStatusKey(
          name: _str(s['name']), type: _str(s['status_type']));
      if (key != 'done') return _str(s['crm_task_status_id']);
    }
    return null;
  }
}

String? _str(Object? v) => v is String ? v : null;
