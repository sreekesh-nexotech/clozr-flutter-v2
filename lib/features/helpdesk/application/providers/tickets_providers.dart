import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/repositories/tickets_repository.dart';
import '../../infrastructure/data_sources/local/tickets_mock_ds.dart';
import '../../infrastructure/repositories/tickets_repository_impl.dart';
import '../../presentation/util/ticket_sla.dart';

/// DI seam: override this in `bootstrap` to inject a real API-backed repo.
final ticketsRepositoryProvider = Provider<TicketsRepository>(
  (ref) => const TicketsRepositoryImpl(TicketsMockDataSource()),
);

/// Async source of all tickets.
final ticketsProvider = FutureProvider<List<Ticket>>(
  (ref) => ref.watch(ticketsRepositoryProvider).getTickets(),
);

/// Look up a single ticket by id (used by the detail screen).
final ticketByIdProvider = Provider.family<Ticket?, String>((ref, id) {
  final tickets = ref.watch(ticketsProvider).valueOrNull;
  if (tickets == null) return null;
  for (final t in tickets) {
    if (t.id == id) return t;
  }
  return null;
});

// ── Tickets list UI state ──

/// Active status tab.
final ticketTabProvider = StateProvider<String>((ref) => 'all');

/// Search query.
final ticketSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final ticketSearchOpenProvider = StateProvider<bool>((ref) => false);

/// "My Tickets" default view — assignees include me (the prototype's default).
final ticketMineProvider = StateProvider<bool>((ref) => true);

/// "Breaching soon" chip — filter to tickets due within the next hour.
final ticketBreachingProvider = StateProvider<bool>((ref) => false);

/// The base list before the status tab (respects My Tickets / Breaching soon).
final ticketBaseProvider = Provider<List<Ticket>>((ref) {
  final all = ref.watch(ticketsProvider).valueOrNull ?? const [];
  final mine = ref.watch(ticketMineProvider);
  final breach = ref.watch(ticketBreachingProvider);
  if (breach) return all.where(ticketBreaching).toList();
  if (mine) return all.where((t) => t.isMine).toList();
  return all.toList();
});

/// Tickets filtered by the active tab + search query.
final visibleTicketsProvider = Provider<List<Ticket>>((ref) {
  final base = ref.watch(ticketBaseProvider);
  final tab = ref.watch(ticketTabProvider);
  final mine = ref.watch(ticketMineProvider);
  final breach = ref.watch(ticketBreachingProvider);
  final q = ref.watch(ticketSearchProvider).trim().toLowerCase();

  Iterable<Ticket> out = base;
  if (tab != 'all') {
    out = out.where((t) => t.status == tab);
  } else if (mine && !breach) {
    out = out.where((t) => t.status != 'resolved' && t.status != 'closed');
  }
  if (q.isNotEmpty) {
    out = out.where((t) {
      final cust = TicketDirectory.customer(t.custId);
      return '${t.subject} ${t.id} ${t.cat} ${cust?.display ?? ''}'.toLowerCase().contains(q);
    });
  }
  return out.toList();
});

/// Per-tab count, mirroring the prototype's `tktCount`.
int ticketTabCount(List<Ticket> all, bool mine, bool breach, String key) {
  final base = mine && !breach
      ? all.where((t) => t.isMine).toList()
      : (breach ? all.where(ticketBreaching).toList() : all);
  if (key == 'all') {
    return mine && !breach ? base.where((t) => t.status != 'resolved' && t.status != 'closed').length : base.length;
  }
  return base.where((t) => t.status == key).length;
}

// ── Helpdesk Home state ──

/// "My Tickets Crossed SLA" value/days segment — true = ₹ Value, false = Days.
final helpSlaValProvider = StateProvider<bool>((ref) => true);

// ── Support Overview (boards) state ──

/// Which SLA-watch sections are expanded (Breached open by default).
final boardExpandedProvider = StateProvider<Map<String, bool>>((ref) => {'breached': true});
