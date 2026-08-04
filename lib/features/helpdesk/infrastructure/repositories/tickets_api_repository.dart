import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/ticket.dart';
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
  Future<List<Ticket>> getTickets() async {
    try {
      final rows = await _remote.fetchTicketRows();
      await AppCache.put(_box, _listKey, rows);
      return TicketsRemoteDataSource.mapTickets(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(_box, _listKey);
        final data = cached?.data;
        if (data is List) return TicketsRemoteDataSource.mapTickets(data);
      }
      rethrow;
    }
  }

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
}
