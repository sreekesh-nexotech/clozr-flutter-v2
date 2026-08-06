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

  /// Mock mode has one seed list and no per-view trimming, so the "record" is
  /// simply the matching seed row — already as complete as it gets.
  @override
  Future<Lead?> getLead(String id) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    for (final lead in _local.fetchLeads()) {
      if (lead.id == id) return lead;
    }
    return null;
  }

  /// Not supported in mock mode: the seed list is immutable, so "persisting" a
  /// stage here would be undone by the next read. Returning null lets the
  /// caller keep the prototype's toast-only behaviour rather than showing a
  /// change that did not happen.
  @override
  Future<Lead?> updateLeadStatus(String leadId, String statusId) async => null;

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
      // `project` is derived from the lead's linked products server-side, not
      // from anything the form submits — there is nothing to echo here.
      project: '',
      value: '—',
      valueNum: 0,
      status: 'new',
      statusDays: 0,
      score: 0,
      source: '',
      owner: 'me',
      team: const ['me'],
      phone: (fields['mobile_no'] ?? '').toString(),
      email: (fields['email'] ?? '').toString(),
      website: (fields['website'] ?? '').toString(),
      industry: '',
      location: '',
      createdOn: '',
      time: 'Just now',
      lastFu: '',
      notif: 0,
    );
  }

  /// No-op — mock mode has nothing to persist to. Returning null keeps the
  /// form on its toast-only path rather than claiming the edit was saved.
  @override
  Future<Lead?> updateLead(String leadId, Map<String, dynamic> fields) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return null;
  }
}
