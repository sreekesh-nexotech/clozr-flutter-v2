import '../../../../app/config/constants.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../crm/domain/entities/audit_entry.dart';
import '../../domain/entities/issue_summary.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/entities/ticket_task.dart';
import '../../domain/repositories/tickets_repository.dart';
import '../data_sources/local/tickets_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class TicketsRepositoryImpl implements TicketsRepository {
  const TicketsRepositoryImpl(this._local);

  final TicketsMockDataSource _local;

  /// Mock mode has no server-side filtering — the seed is small and the
  /// providers narrow it locally, exactly as they did before.
  @override
  Future<List<Ticket>> getTickets({Map<String, dynamic> filters = const {}}) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchTickets();
  }

  /// No per-ticket endpoint in mock mode; null keeps the screen on the seed row.
  @override
  Future<Ticket?> getTicket(String id) async => null;

  /// No catalog endpoint in mock mode; empty sends callers to the built-in
  /// status vocabulary.
  @override
  Future<List<CatalogOption>> getIssueStatuses() async => const [];

  /// No type catalog in mock mode; empty keeps the built-in category chips.
  @override
  Future<List<CatalogOption>> getIssueTypes() async => const [];

  /// No activity endpoint in mock mode; the screen keeps its derived trail.
  @override
  Future<List<AuditEntry>> getActivity(String issueId,
          {Map<String, String> names = const {}}) async =>
      const [];

  /// No summary endpoint in mock mode; null sends the screen to its local
  /// derivation, exactly as before.
  @override
  Future<IssueSummary?> getSummary(Map<String, dynamic> filters) async => null;

  /// No counts endpoint either; empty means "count the loaded rows".
  @override
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters) async =>
      const {};

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

  /// Mock write: no-op — the detail screen's local override handles the UX.
  @override
  Future<void> setAssignee(String id, String? userId) async {}

  /// No linked-tasks endpoint in mock mode; empty sends the card back to the
  /// seed's own `taskId`.
  @override
  Future<List<TicketTask>> getLinkedTasks(String issueId) async => const [];

  /// Mock write: echoes the submitted subject so the create flow keeps working
  /// offline. The seed is untouched.
  @override
  Future<TicketTask?> createLinkedTask(String issueId,
          {required String subject, String? priority}) async =>
      TicketTask(id: '', subject: subject.trim(), priority: priority ?? '');
}
