import '../entities/crm_task.dart';

/// Abstract contract for CRM task data.
abstract class CrmTasksRepository {
  Future<List<CrmTask>> getTasks();

  /// Creates a task from the Add-task sheet's fields
  /// (`title` / `task_type` / `due_date` / `description`). Returns the created
  /// task, or null when the response shape was unexpected.
  Future<CrmTask?> createTask(Map<String, dynamic> fields);

  /// Moves a task to the status matching the UI key
  /// (`todo | inprogress | blocked | done`).
  Future<void> setTaskStatusByKey(String taskId, String uiStatusKey);
}
