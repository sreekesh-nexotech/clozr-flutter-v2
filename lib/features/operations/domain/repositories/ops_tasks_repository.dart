import '../../../crm/domain/entities/audit_entry.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../entities/ops_task.dart';

/// Abstract contract for operations-task data. The presentation layer depends
/// only on this; the source (mock vs REST API) is an infrastructure detail.
abstract class OpsTasksRepository {
  /// [filters] are `/projects/tasks/` query params from the drawer, the status
  /// tabs and the My-tasks toggle, applied server-side.
  Future<List<OpsTask>> getOpsTasks({Map<String, dynamic> filters = const {}});

  /// The org's project-task statuses. Empty means "no catalog".
  Future<List<CatalogOption>> getOpsTaskStatuses();

  /// Per-status tab counts under the same [filters] as the list
  /// (`operations-task.md` §2), keyed by status name plus `'all'`. Empty means
  /// "no counts" — count locally.
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters);

  /// The lanes defined on one project. Empty means "no groups" — the caller
  /// offers "No group" alone rather than guessing lane names.
  Future<List<CatalogOption>> getTaskGroups(String projectId);

  /// Creates a PMO task from API-shaped [fields] (`subject`, `project`,
  /// `priority`, `description`, …). Returns the created task when the backend
  /// echoes a usable row, null otherwise (mock mode always null).
  Future<OpsTask?> createOpsTask(Map<String, dynamic> fields);

  /// Partially updates task [id] with API-shaped [fields].
  Future<void> updateOpsTask(String id, Map<String, dynamic> fields);

  /// Deletes task [id].
  ///
  /// Throws on refusal — a `409` names the tasks that depend on this one, and
  /// that list is the only way the user learns what to unblock first.
  Future<void> deleteOpsTask(String id);

  /// Makes [taskId] wait on [dependsOn].
  ///
  /// Throws on refusal — a duplicate, a cycle, a cross-project blocker and a
  /// self-dependency are all `400`s the user has to see.
  Future<void> addDependency({required String taskId, required String dependsOn});

  /// Removes a dependency edge by its own id (`task_depends_on_id`).
  Future<void> removeDependency(String edgeId);

  /// One task's direct subtasks. [closedStatusIds] decides which rows read as
  /// ticked; pass the org's closed project-task statuses.
  ///
  /// Empty in mock mode, where the checklist lives on the seed record itself.
  Future<List<Subtask>> getSubtasks(
    String parentId, {
    Set<String> closedStatusIds = const {},
  });

  /// Adds a subtask under [parentId]. Throws on refusal — the subject and the
  /// parent's own validation both come back as `400`s.
  Future<void> createSubtask({
    required String parentId,
    required String subject,
    String projectId = '',
  });

  /// One task's activity feed. Empty means "nothing to show" — mock mode, a
  /// failed call, or a task with no recorded history — never an error.
  ///
  /// [statusNames] resolves the status uuid the server leaves raw in a
  /// "Status changed to …" summary.
  Future<List<AuditEntry>> getTaskActivity(
    String taskId, {
    Map<String, String> statusNames = const {},
  });

  /// One task in its **full shape** — the description, expected start,
  /// department and dependency edges the list's slim rows drop.
  ///
  /// Null when unavailable (mock mode, a failed call); the caller keeps the
  /// list row it already has.
  Future<OpsTask?> getOpsTask(String id);
}
