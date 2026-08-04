import 'package:intl/intl.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../core/network/api_endpoints.dart';
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
  static const int _maxPages = 3;

  /// Neutral colour tag for API rows — same `OpsColorTag(name, hex)` shape the
  /// mock seed uses, with an empty name and the grey token.
  static const OpsColorTag neutralTag = OpsColorTag('', AppColors.textMuted);

  /// All PMO tasks visible to the caller — slim rows, up to 3 pages of 100.
  Future<List<OpsTask>> fetchOpsTasks() async {
    final out = <OpsTask>[];
    for (var page = 1; page <= _maxPages; page++) {
      final body = await _api.get(ApiEndpoints.projectTasks, query: {
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

  // ── mapping ──

  /// `?view=list` slim row (or a full row — create/detail responses share the
  /// field names) → [OpsTask]. Returns null for rows without a `task_id`;
  /// every other field degrades to a safe default instead of throwing.
  ///
  /// `projId` is the `project` UUID, matching `Project.id` (which is always
  /// the `project_id` UUID) so cross-references resolve.
  ///
  /// Known slim-row limitation: the API exposes only
  /// `pending_dependency_count`, not the dependency edges, so `waitingOn`
  /// stays empty and the UI's "Waiting on N" badge (derived from
  /// `waitingOn.length`) is hidden until task-detail wiring lands.
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

    return OpsTask(
      id: id,
      subject: row['subject'] as String? ?? '',
      projId: row['project'] as String? ?? '',
      group: row['task_group_name'] as String? ?? 'No group',
      status: opsTaskStatusKey(name: row['status_name'] as String?),
      pri: priorityKey(row['priority'] as String?),
      assignees: assignees,
      milestone: row['is_milestone'] == true,
      start: '', // exp_start_date absent on slim rows
      startTime: '',
      end: absoluteDate(endDate),
      endTime: _timeOf(endRaw, endDate),
      endISO: endRaw,
      expHrs: 0,
      progress: _progress(row),
      weight: 1,
      dept: '',
      color: neutralTag,
      subtasks: const [], // slim rows expose subtask_count only
      waitingOn: const [], // see limitation note above
      notes: const [],
      desc: row['description'] as String? ?? '',
    );
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
