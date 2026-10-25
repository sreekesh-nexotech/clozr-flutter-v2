import '../entities/crm_task.dart';
import '../entities/view_schema.dart';

/// Abstract contract for CRM task data.
abstract class CrmTasksRepository {
  Future<List<CrmTask>> getTasks();

  /// The task list narrowed server-side by the webapp's list params
  /// (`status__in`, `assigned_to__not`, `search`, …).
  Future<List<CrmTask>> getTasksQuery(Map<String, dynamic> query);

  /// The tasks linked to one lead — the Tasks tab on the lead detail screen.
  /// Scoped by the backend, not by filtering the org-wide list.
  Future<List<CrmTask>> getTasksForLead(String leadId);

  /// The org's Task detail layout, which drives the "Task information" panel.
  ///
  /// Empty means "no opinion" — mock mode, a failed fetch, or an org with no
  /// config — and the panel falls back to its built-in rows.
  Future<ViewSchema> getTaskDetailSchema();

  /// The raw record row for one task, for the schema-driven detail panel.
  ///
  /// Unmapped by design: the panel renders the columns the org configured, so
  /// it needs values keyed by field name. Null when no such task is visible.
  /// [isFollowup] adds `?is_followup=true` — without it a follow-up is a 404.
  Future<Map<String, dynamic>?> getTaskRow(String id, {bool isFollowup = false});

  /// Creates a task from the Add-task sheet's fields
  /// (`title` / `task_type` / `due_date` / `description`). Returns the created
  /// task, or null when the response shape was unexpected.
  Future<CrmTask?> createTask(Map<String, dynamic> fields);

  /// The org's Task layout for the mobile list card
  /// (`GET /crm/tasks/schema/?view_type=mobile`, falling back to `list`).
  ///
  /// Empty means "no opinion" — mock mode, a failed fetch, or an org with no
  /// config — and the card then renders its built-in field set.
  Future<ViewSchema> getTaskListSchema();

  /// `PATCH /crm/tasks/{id}/` — saves an edit built from the org's schema.
  /// [isFollowup] adds `?is_followup=true`: a follow-up is only found under
  /// that flag, and the plain task URL answers 404 for it.
  Future<CrmTask?> updateTask(String id, Map<String, dynamic> fields, {bool isFollowup = false});

  /// `DELETE /crm/tasks/{id}/` (`?is_followup=true` for a follow-up).
  Future<void> deleteTask(String id, {bool isFollowup = false});

  /// Moves a task to the status matching the UI key
  /// (`todo | inprogress | blocked | done`).
  Future<void> setTaskStatusByKey(String taskId, String uiStatusKey);
}
