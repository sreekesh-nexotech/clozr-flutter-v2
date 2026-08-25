// Saving an edit invalidated `ticketsProvider`, but the rows live one level
// down in `ticketsScopedProvider` — a family that nothing dropped. Re-running
// the derived provider just re-read the same cached future, so the detail
// screen came back from the edit form still showing the old values, and every
// pull-to-refresh on the helpdesk screens was a no-op too.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/domain/entities/audit_entry.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/helpdesk/application/providers/tickets_providers.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/issue_summary.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/ticket.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/ticket_task.dart';
import 'package:clozrapp/features/helpdesk/domain/repositories/tickets_repository.dart';

Ticket _ticket(String subject) => Ticket(
      id: 'i-1',
      subject: subject,
      cat: 'Request',
      custId: '',
      contact: '',
      channel: 'Email',
      status: 'open',
      pri: 'Medium',
      assignees: const [],
      product: null,
      projId: null,
      taskId: null,
      created: '',
      responded: null,
      resolved: null,
      respByISO: null,
      respByLabel: null,
      resolveByISO: null,
      resolveByLabel: null,
      desc: '',
    );

/// Serves a new subject on every fetch, so a stale read is visible.
class _CountingRepo implements TicketsRepository {
  int fetches = 0;

  @override
  Future<List<Ticket>> getTickets({Map<String, dynamic> filters = const {}}) async {
    fetches++;
    return [_ticket('subject-$fetches')];
  }

  @override
  Future<Ticket?> getTicket(String id) async => null;

  @override
  Future<List<CatalogOption>> getIssueStatuses() async => const [];

  @override
  Future<List<CatalogOption>> getIssueTypes() async => const [];

  @override
  Future<List<AuditEntry>> getActivity(String issueId,
          {Map<String, String> names = const {}}) async =>
      const [];

  @override
  Future<IssueSummary?> getSummary(Map<String, dynamic> filters) async => null;

  @override
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters) async => const {};

  @override
  Future<Ticket?> createTicket(Map<String, dynamic> fields) async => null;

  @override
  Future<void> updateTicket(String id, Map<String, dynamic> fields) async {}

  @override
  Future<void> setTicketStatusByKey(String id, String uiStatusKey) async {}

  @override
  Future<void> setAssignee(String id, String? userId) async {}

  @override
  Future<List<TicketTask>> getLinkedTasks(String issueId) async => const [];

  @override
  Future<TicketTask?> createLinkedTask(String issueId,
          {required String subject, String? priority}) async =>
      null;
}

void main() {
  late _CountingRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _CountingRepo();
    container = ProviderContainer(
      overrides: [ticketsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  test('refreshTickets refetches, so an edited ticket comes back changed',
      () async {
    final sub = container.listen(ticketsProvider, (_, __) {}, fireImmediately: true);
    addTearDown(sub.close);
    await container.read(ticketsProvider.future);
    expect(repo.fetches, 1);
    expect(container.read(ticketByIdProvider('i-1'))?.subject, 'subject-1');

    container.invalidate(ticketsScopedProvider); // what refreshTickets does
    await container.read(ticketsProvider.future);

    expect(repo.fetches, 2, reason: 'the server must be asked again');
    expect(container.read(ticketByIdProvider('i-1'))?.subject, 'subject-2',
        reason: 'the detail screen must see the saved edit');
  });

  test('the filtered list refetches from the same call', () async {
    final sub = container.listen(ticketsFilteredProvider, (_, __) {},
        fireImmediately: true);
    addTearDown(sub.close);
    await container.read(ticketsFilteredProvider.future);
    expect(repo.fetches, 1);

    container.invalidate(ticketsScopedProvider);
    await container.read(ticketsFilteredProvider.future);
    expect(repo.fetches, 2);
  });

  test('invalidating the derived provider alone is not enough', () async {
    final sub = container.listen(ticketsProvider, (_, __) {}, fireImmediately: true);
    addTearDown(sub.close);
    await container.read(ticketsProvider.future);

    // The old call site: re-runs the body, re-reads the cached scoped future.
    container.invalidate(ticketsProvider);
    await container.read(ticketsProvider.future);
    expect(repo.fetches, 1,
        reason: 'documents why refreshTickets exists — this served stale rows');
  });
}
