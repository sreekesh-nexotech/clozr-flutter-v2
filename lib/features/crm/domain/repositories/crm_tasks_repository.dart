import '../entities/crm_task.dart';

/// Abstract contract for CRM task data.
abstract class CrmTasksRepository {
  Future<List<CrmTask>> getTasks();

  /// The tasks linked to one lead — the Tasks tab on the lead detail screen.
  /// Scoped by the backend, not by filtering the org-wide list.
  Future<List<CrmTask>> getTasksForLead(String leadId);

  /// Creates a task from the Add-task sheet's fields
  /// (`title` / `task_type` / `due_date` / `description`). Returns the created
  /// task, or null when the response shape was unexpected.
  Future<CrmTask?> createTask(Map<String, dynamic> fields);

  /// Moves a task to the status matching the UI key
  /// (`todo | inprogress | blocked | done`).
  Future<void> setTaskStatusByKey(String taskId, String uiStatusKey);
}
