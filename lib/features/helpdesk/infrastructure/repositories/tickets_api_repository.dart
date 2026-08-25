import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../crm/domain/entities/audit_entry.dart';
import '../../domain/entities/issue_summary.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/entities/ticket_task.dart';
import '../../domain/repositories/tickets_repository.dart';
import '../data_sources/remote/tickets_remote_ds.dart';

/// API-backed tickets repository.
///
/// Reads: remote first; the raw rows are cached in Hive so a network/timeout
/// failure serves the last good copy instead of an error. Writes: remote only —
/// the list cache key is dropped so the next read refetches fresh data.
class TicketsApiRepository implements TicketsRepository {
  TicketsApiRepository(this._remote);

  final TicketsRemoteDataSource _remote;

  static const String _box = AppCache.helpdeskCache;
  static const String _listKey = 'tickets';

  @override
  Future<List<Ticket>> getTickets({Map<String, dynamic> filters = const {}}) async {
    try {
      final rows = await _remote.fetchTicketRows(filters: filters);
      // Only the unfiltered list is cached: a filtered page is not the list,
      // and serving it back offline would silently narrow what the user sees.
      if (filters.isEmpty) await AppCache.put(_box, _listKey, rows);
      return TicketsRemoteDataSource.mapTickets(rows);
    } on AppError catch (e) {
      if (filters.isEmpty &&
          (e.type == AppErrorType.network || e.type == AppErrorType.timeout)) {
        final cached = AppCache.get(_box, _listKey);
        final data = cached?.data;
        if (data is List) return TicketsRemoteDataSource.mapTickets(data);
      }
      rethrow;
    }
  }

  @override
  Future<Ticket?> getTicket(String id) => _remote.fetchTicket(id);

  @override
  Future<List<CatalogOption>> getIssueStatuses() => _remote.fetchIssueStatuses();

  @override
  Future<List<CatalogOption>> getIssueTypes() => _remote.fetchIssueTypes();

  @override
  Future<List<AuditEntry>> getActivity(String issueId,
          {Map<String, String> names = const {}}) =>
      _remote.fetchActivity(issueId, names: names);

  @override
  Future<IssueSummary?> getSummary(Map<String, dynamic> filters) =>
      _remote.fetchSummary(filters: filters);

  @override
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters) =>
      _remote.fetchStatusCounts(filters: filters);

  @override
  Future<Ticket?> createTicket(Map<String, dynamic> fields) async {
    final ticket = await _remote.createTicket(fields);
    await AppCache.remove(_box, _listKey);
    return ticket;
  }

  @override
  Future<void> updateTicket(String id, Map<String, dynamic> fields) async {
    await _remote.updateTicket(id, fields);
    await AppCache.remove(_box, _listKey);
  }

  @override
  Future<void> setTicketStatusByKey(String id, String uiStatusKey) async {
    await _remote.setStatusByKey(id, uiStatusKey);
    await AppCache.remove(_box, _listKey);
  }

  @override
  Future<void> setAssignee(String id, String? userId) async {
    await _remote.setAssignee(id, userId);
    await AppCache.remove(_box, _listKey);
  }

  @override
  Future<List<TicketTask>> getLinkedTasks(String issueId) =>
      _remote.fetchLinkedTasks(issueId);

  @override
  Future<TicketTask?> createLinkedTask(String issueId,
      {required String subject, String? priority}) async {
    final task = await _remote.createLinkedTask(issueId,
        subject: subject, priority: priority);
    // `has_linked_tasks` on the list row changes with this write.
    await AppCache.remove(_box, _listKey);
    return task;
  }
}
