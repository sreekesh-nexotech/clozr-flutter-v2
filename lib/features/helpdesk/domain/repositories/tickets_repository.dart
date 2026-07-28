import '../entities/ticket.dart';

/// Abstract contract for ticket data. The presentation layer depends only on
/// this; whether tickets come from a mock source or a REST API is an
/// infrastructure detail.
abstract class TicketsRepository {
  Future<List<Ticket>> getTickets();
}
