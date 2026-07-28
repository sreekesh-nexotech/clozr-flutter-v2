import '../../../../app/config/constants.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/leads_repository.dart';
import '../data_sources/local/leads_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class LeadsRepositoryImpl implements LeadsRepository {
  const LeadsRepositoryImpl(this._local);

  final LeadsMockDataSource _local;

  @override
  Future<List<Lead>> getLeads() async {
    // Simulated latency so skeleton/loading states are exercised.
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchLeads();
  }
}
