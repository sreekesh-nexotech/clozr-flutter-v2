import '../domain/entities/crm_task.dart';
import '../domain/entities/followup.dart';
import '../domain/entities/view_schema.dart';
import 'schema_columns.dart';

/// Schema-configured columns for the Task and Follow-up cards.
///
/// Both cards drew a fixed set of slots, so a column the org added outside that
/// set rendered as nothing. These give them the same open-ended strip the Leads
/// and Customers cards have.

/// Columns the task card draws itself.
const Set<String> kTaskCardFrameColumns = {
  'title',
  'description',
  'task_type',
  'related_to',
  'status',
  'status_name',
  'priority',
  'due_date',
  'assigned_to',
  'assignees',
};

/// Columns the follow-up card draws itself.
const Set<String> kFollowupCardFrameColumns = {
  'title',
  'description',
  'task_type',
  'related_to',
  'status',
  'status_name',
  'priority',
  'due_date',
  'due_time',
  'assigned_to',
  'assignees',
};

List<({String label, String value})> taskExtraColumns(
  CrmTask task,
  ViewSchema schema,
) =>
    schemaExtraColumns(schema, kTaskCardFrameColumns,
        (c) => taskColumnText(task, c));

String? taskColumnText(CrmTask task, ViewColumn column) {
  final typed = switch (column.name) {
    'title' => task.title,
    'description' => task.description,
    'task_type' => task.type,
    'priority' => task.priority,
    'due_date' => task.due,
    _ => null,
  };
  if (typed != null && typed.trim().isNotEmpty) return typed.trim();
  return rawColumnText(task.raw, column);
}

List<({String label, String value})> followupExtraColumns(
  Followup followup,
  ViewSchema schema,
) =>
    schemaExtraColumns(schema, kFollowupCardFrameColumns,
        (c) => followupColumnText(followup, c));

String? followupColumnText(Followup followup, ViewColumn column) {
  final typed = switch (column.name) {
    'title' => followup.title,
    'description' => followup.description,
    'task_type' => followup.kind,
    'priority' => followup.priority,
    'due_date' => followup.due,
    'due_time' => followup.time,
    _ => null,
  };
  if (typed != null && typed.trim().isNotEmpty) return typed.trim();
  return rawColumnText(followup.raw, column);
}
