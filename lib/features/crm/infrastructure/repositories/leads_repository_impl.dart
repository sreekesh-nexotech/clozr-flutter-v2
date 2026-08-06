import '../../../../app/config/constants.dart';
import '../../../../data/api/user_directory.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/leads_repository.dart';
import '../data_sources/local/leads_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class LeadsRepositoryImpl implements LeadsRepository {
  const LeadsRepositoryImpl(this._local);

  final LeadsMockDataSource _local;

  /// [filters] is accepted for interface parity and ignored: the seed source is
  /// a plain list with nothing to run query params against. Callers keep the
  /// client-side matcher for mock mode, so the drawer still filters there.
  @override
  Future<List<Lead>> getLeads({
    bool mineOnly = false,
    Map<String, dynamic> filters = const {},
  }) async {
    // Simulated latency so skeleton/loading states are exercised.
    await Future<void>.delayed(AppConstants.mockLatency);
    final leads = _local.fetchLeads();
    // Stands in for the server's `?is_teams=true`, so the toggle behaves the
    // same in mock mode as it does against the API.
    return mineOnly ? leads.where((l) => l.isMine).toList() : leads;
  }

  /// Local echo — mock mode has no backend, so the "created" lead is built
  /// from the submitted fields (never persisted; mock behavior unchanged).
  @override
  Future<Lead?> createLead(Map<String, dynamic> fields) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    final name = (fields['lead_name'] ?? '').toString();
    return Lead(
      id: 'L${DateTime.now().millisecondsSinceEpoch.remainder(100000)}',
      name: name,
      initials: UserDirectory.initialsOf(name),
      company: (fields['organization_name'] ?? '').toString(),
      project: (fields['purpose'] ?? '').toString(),
      value: '—',
      valueNum: 0,
      status: 'new',
      statusDays: 0,
      score: 0,
      source: '',
      owner: 'me',
      team: const ['me'],
      phone: (fields['phone'] ?? '').toString(),
      email: (fields['email'] ?? '').toString(),
      website: '',
      industry: '',
      location: '',
      createdOn: '',
      time: 'Just now',
      lastFu: '',
      notif: 0,
    );
  }
}
