import '../entities/ticket.dart';

/// Abstract contract for ticket data. The presentation layer depends only on
/// this; whether tickets come from a mock source or a REST API is an
/// infrastructure detail.
abstract class TicketsRepository {
  Future<List<Ticket>> getTickets();

  /// Creates a ticket from UI-level fields (`subject`, `description`,
  /// `priority`, `channel`, `customer_id`). Returns the created ticket when
  /// the backend echoes it, null otherwise.
  Future<Ticket?> createTicket(Map<String, dynamic> fields);

  /// Partially updates a ticket (subject/description/priority …).
  Future<void> updateTicket(String id, Map<String, dynamic> fields);

  /// Moves a ticket to the org status matching a UI status key
  /// (`new | open | pending | resolved | closed`).
  Future<void> setTicketStatusByKey(String id, String uiStatusKey);
}
