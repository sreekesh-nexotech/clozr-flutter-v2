import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../crm/domain/entities/audit_entry.dart';
import '../entities/issue_summary.dart';
import '../entities/ticket.dart';
import '../entities/ticket_task.dart';

/// Abstract contract for ticket data. The presentation layer depends only on
/// this; whether tickets come from a mock source or a REST API is an
/// infrastructure detail.
abstract class TicketsRepository {
  /// [filters] are `/crm/issues/` query params (`issue-filters.md` Part 4),
  /// applied server-side. Empty means the whole visible list.
  Future<List<Ticket>> getTickets({Map<String, dynamic> filters});

  /// One ticket by id. Null when unavailable (mock mode, no permission, a
  /// failed call), which callers read as "fall back to the list row".
  Future<Ticket?> getTicket(String id);

  /// The org's own issue statuses. Empty when unavailable, which callers read
  /// as "use the built-in vocabulary".
  Future<List<CatalogOption>> getIssueStatuses();

  /// The org's own issue types. Empty when unavailable, which callers read as
  /// "use the built-in vocabulary".
  Future<List<CatalogOption>> getIssueTypes();

  /// One ticket's own activity feed. Empty when unavailable.
  Future<List<AuditEntry>> getActivity(String issueId, {Map<String, String> names});

  /// The Support Overview figures under the same [filters]. Null when
  /// unavailable, which callers read as "count the loaded tickets instead".
  Future<IssueSummary?> getSummary(Map<String, dynamic> filters);

  /// Per-status tab counts under the same [filters], keyed by
  /// `issue_status_id` plus `'all'`. Empty when unavailable.
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters);

  /// Creates a ticket from UI-level fields (`subject`, `description`,
  /// `priority`, `channel`, `customer_id`). Returns the created ticket when
  /// the backend echoes it, null otherwise.
  Future<Ticket?> createTicket(Map<String, dynamic> fields);

  /// Partially updates a ticket (subject/description/priority …).
  Future<void> updateTicket(String id, Map<String, dynamic> fields);

  /// Moves a ticket to the org status matching a UI status key
  /// (`new | open | pending | resolved | closed`).
  Future<void> setTicketStatusByKey(String id, String uiStatusKey);

  /// Sets the ticket's assignee (`assigned_to`). A ticket holds **one**
  /// assignee; null clears it.
  Future<void> setAssignee(String id, String? userId);

  /// The Operations tasks raised from this ticket. Empty when unavailable.
  Future<List<TicketTask>> getLinkedTasks(String issueId);

  /// Raises an Operations task against this ticket. `subject` is the only
  /// field the backend requires.
  Future<TicketTask?> createLinkedTask(String issueId,
      {required String subject, String? priority});
}
