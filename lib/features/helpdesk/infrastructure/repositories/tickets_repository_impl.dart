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
}
