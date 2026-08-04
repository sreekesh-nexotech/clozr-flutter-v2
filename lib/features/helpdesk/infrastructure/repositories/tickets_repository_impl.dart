import '../../../../app/config/constants.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/repositories/tickets_repository.dart';
import '../data_sources/local/tickets_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class TicketsRepositoryImpl implements TicketsRepository {
  const TicketsRepositoryImpl(this._local);

  final TicketsMockDataSource _local;

  @override
  Future<List<Ticket>> getTickets() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchTickets();
  }

  /// Mock write: echoes a local ticket built from the submitted fields so the
  /// create flow keeps working offline. The seed list itself is untouched.
  @override
  Future<Ticket?> createTicket(Map<String, dynamic> fields) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return Ticket(
      id: 'TKT-${DateTime.now().millisecondsSinceEpoch % 100000}',
      subject: (fields['subject'] as String?)?.trim() ?? '',
      cat: (fields['category'] as String?) ?? 'Query',
      custId: (fields['customer_id'] as String?) ?? '',
      contact: '',
      channel: (fields['channel'] as String?) ?? 'Email',
      status: 'new',
      pri: (fields['priority'] as String?) ?? 'Medium',
      assignees: const ['me'],
      product: null,
      projId: null,
      taskId: null,
      created: 'Just now',
      responded: null,
      resolved: null,
      respByISO: null,
      respByLabel: null,
      resolveByISO: null,
      resolveByLabel: null,
      desc: (fields['description'] as String?) ?? '',
    );
  }

  /// Mock write: no-op — the detail/edit screens already update their local
  /// copy for instant UX.
  @override
  Future<void> updateTicket(String id, Map<String, dynamic> fields) async {}

  /// Mock write: no-op — the detail screen's local copyWith handles the UX.
  @override
  Future<void> setTicketStatusByKey(String id, String uiStatusKey) async {}
}
