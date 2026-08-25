import '../../../../app/config/constants.dart';
import '../../../crm/domain/entities/audit_entry.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../domain/entities/ops_task.dart';
import '../../domain/repositories/ops_tasks_repository.dart';
import '../data_sources/local/ops_tasks_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one when the
/// API lands — the interface and every caller stay the same.
class OpsTasksRepositoryImpl implements OpsTasksRepository {
  const OpsTasksRepositoryImpl(this._local);

  final OpsTasksMockDataSource _local;

  @override
  Future<List<OpsTask>> getOpsTasks({Map<String, dynamic> filters = const {}}) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchOpsTasks();
  }

  /// Mock writes are harmless no-ops: mock-mode screens keep their local
  /// toast-and-pop behavior and never read the result.
  @override
  Future<OpsTask?> createOpsTask(Map<String, dynamic> fields) async => null;

  @override
  Future<void> updateOpsTask(String id, Map<String, dynamic> fields) async {}

  /// Mock mode has no org catalog; the drawer falls back to the built-ins.
  @override
  Future<List<CatalogOption>> getOpsTaskStatuses() async => const [];

  /// No aggregate endpoint in mock mode; the strip counts the seed rows.
  @override
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters) async =>
      const {};

  /// Nothing to delete against; the screen's toast is the whole behaviour.
  @override
  Future<void> deleteOpsTask(String id) async {}

  /// Mock edges live in the seed only; the screen keeps its local behaviour.
  @override
  Future<void> addDependency({required String taskId, required String dependsOn}) async {}

  @override
  Future<void> removeDependency(String edgeId) async {}

  /// No retrieve endpoint in mock mode; the seed row is all there is.
  @override
  Future<OpsTask?> getOpsTask(String id) async => null;

  /// The seed record carries its own checklist, so there is nothing to fetch —
  /// the screen keeps editing that list in memory.
  @override
  Future<List<Subtask>> getSubtasks(
    String parentId, {
    Set<String> closedStatusIds = const {},
  }) async =>
      const [];

  @override
  Future<void> createSubtask({
    required String parentId,
    required String subject,
    String projectId = '',
  }) async {}

  /// No audit trail in mock mode; the screen falls back to its derived rows.
  @override
  Future<List<AuditEntry>> getTaskActivity(
    String taskId, {
    Map<String, String> statusNames = const {},
  }) async =>
      const [];

  /// Mock mode has no lane catalog; the picker falls back to the seed groups.
  @override
  Future<List<CatalogOption>> getTaskGroups(String projectId) async => const [];
}
