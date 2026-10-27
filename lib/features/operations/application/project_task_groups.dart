import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/app_error.dart';
import '../../../core/network/network_providers.dart';
import 'providers/ops_tasks_providers.dart';
import 'providers/projects_providers.dart';
import '../../../core/network/paginated.dart';
import '../../crm/domain/entities/audit_entry.dart';
import '../../crm/infrastructure/data_sources/remote/audit_log_remote_ds.dart';
import '../infrastructure/data_sources/remote/ops_tasks_remote_ds.dart';

/// Task-group (lane) writes for the project's Tasks tab — webapp
/// `projectDetail.api.ts` §12.2: `POST /projects/task-groups/ {project, title}`,
/// `PATCH …/{id}/ {title}`, `DELETE …/{id}/` (its tasks fall into "No group").
///
/// Each returns null on success or the server's message, with the shell's raw
/// toast withdrawn so the caller shows it once.
Future<String?> createTaskGroup(WidgetRef ref, String projectId, String title) =>
    _write(ref, projectId, () => ref
        .read(apiServiceProvider)
        .post(ApiEndpoints.taskGroups, body: {'project': projectId, 'title': title}));

Future<String?> renameTaskGroup(WidgetRef ref, String projectId, String groupId, String title) =>
    _write(ref, projectId, () => ref
        .read(apiServiceProvider)
        .patch('${ApiEndpoints.taskGroups}$groupId/', body: {'title': title}));

Future<String?> deleteTaskGroup(WidgetRef ref, String projectId, String groupId) =>
    _write(ref, projectId,
        () => ref.read(apiServiceProvider).delete('${ApiEndpoints.taskGroups}$groupId/'));

Future<String?> _write(WidgetRef ref, String projectId, Future<Object?> Function() call) async {
  if (!ApiConfig.apiEnabled) return null;
  try {
    await call();
  } on AppError catch (e) {
    ref.read(apiServiceProvider).handled(e);
    return e.bareMessage;
  }
  // The lanes, and the project's tasks (a deleted lane re-homes them).
  ref.invalidate(taskGroupsProvider(projectId));
  ref.invalidate(projectTasksProvider(projectId));
  return null;
}

/// The linked quote's number ("QTN-00008") for the project's "Linked quote"
/// row — webapp `useQuoteQuery`. Null while loading or when it cannot be read;
/// the row then says "Open quote".
final linkedQuoteNumberProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, quoteId) async {
  if (!ApiConfig.apiEnabled || quoteId.isEmpty) return null;
  try {
    final body = await ref
        .watch(apiServiceProvider)
        .get('/quotations/quotations/$quoteId/', quiet: true);
    if (body is! Map) return null;
    final n = '${body['quotation_number'] ?? ''}'.trim();
    return n.isEmpty ? null : n;
  } on Object {
    return null;
  }
});

/// The project's audit trail — webapp `GET /projects/projects/{id}/activity/`
/// (newest first, archived projects too). Each row's recorded diff is the
/// whole story on an update ("Project Manager: — → Cijo George"); otherwise
/// the server's summary, with any status id named from the catalogue.
/// Refetched off the write tick. Null when it could not be read.
final projectFeedProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>?, String>((ref, projectId) async {
  if (!ApiConfig.apiEnabled || projectId.isEmpty) return const [];
  ref.watch(apiWriteTickProvider);
  final statusNames = {
    for (final s in ref.watch(projectStatusOptionsProvider)) s.id: s.name,
  };
  try {
    final body = await ref.watch(apiServiceProvider).get(
      '/projects/projects/$projectId/activity/',
      query: {'page_size': 50, 'include_archived': 'true'},
      quiet: true,
    );
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    final out = <AuditEntry>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final changes = row['changes'];
      final diff = '${row['action'] ?? 'update'}' == 'update' && changes is Map
          ? AuditLogRemoteDataSource.formatAuditDiff(changes)
          : null;
      final base = OpsTasksRemoteDataSource.mapActivity(
        {...row, if ('${row['summary'] ?? ''}'.trim().isEmpty) 'summary': 'Project updated'},
        i,
        statusNames: statusNames,
      );
      if (base == null) continue;
      out.add(diff == null || diff.isEmpty
          ? base
          : AuditEntry(
              id: base.id,
              kind: base.kind,
              title: diff,
              subtitle: '',
              at: base.at,
              actor: base.actor,
            ));
    }
    return out;
  } on Object {
    return null;
  }
});
