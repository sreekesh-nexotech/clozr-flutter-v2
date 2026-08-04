import '../entities/ops_task.dart';

/// Abstract contract for operations-task data. The presentation layer depends
/// only on this; the source (mock vs REST API) is an infrastructure detail.
abstract class OpsTasksRepository {
  Future<List<OpsTask>> getOpsTasks();

  /// Creates a PMO task from API-shaped [fields] (`subject`, `project`,
  /// `priority`, `description`, …). Returns the created task when the backend
  /// echoes a usable row, null otherwise (mock mode always null).
  Future<OpsTask?> createOpsTask(Map<String, dynamic> fields);

  /// Partially updates task [id] with API-shaped [fields].
  Future<void> updateOpsTask(String id, Map<String, dynamic> fields);
}
