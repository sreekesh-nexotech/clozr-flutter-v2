/// One Operations task raised from a ticket (`GET /issues/{issue_id}/tasks/`).
///
/// The backend serves these with the **projects** `TaskSerializer` — a linked
/// task *is* a `projects.Task`, so [id] is a `task_id` the Operations screens
/// open. Only the fields the ticket's Linked-tasks card renders are kept;
/// anything richer belongs to the Operations feature's own entity.
class TicketTask {
  const TicketTask({
    required this.id,
    required this.subject,
    this.status = '',
    this.priority = '',
    this.projectId,
    this.assigneeName = '',
  });

  final String id;
  final String subject;

  /// The org's task-status name, empty when the task has none yet.
  final String status;
  final String priority;
  final String? projectId;
  final String assigneeName;

  /// What the card prints. A task always has a subject (the API requires it),
  /// but a truncated payload should still show something addressable.
  String get display => subject.isNotEmpty ? subject : id;
}
