import '../../../../app/config/constants.dart';
import '../../domain/entities/followup.dart';
import '../../domain/repositories/followups_repository.dart';
import '../data_sources/local/followups_mock_ds.dart';

/// Mock-backed implementation.
class FollowupsRepositoryImpl implements FollowupsRepository {
  const FollowupsRepositoryImpl(this._local);

  final FollowupsMockDataSource _local;

  @override
  Future<List<Followup>> getFollowups({Map<String, dynamic> filters = const {}}) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchFollowups();
  }

  /// Mock mode has no server-side filter, so the seed is narrowed here — the
  /// same result the API returns for `?related_to=lead&related_to_id=…`.
  @override
  Future<List<Followup>> getFollowupsForLead(String leadId) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchFollowups().where((f) => f.leadId == leadId).toList();
  }

  /// Local echo — builds the follow-up the way the Add-follow-up sheet does.
  /// Mock mode keeps its session-draft flow; this honours the contract.
  @override
  Future<Followup?> createFollowup(Map<String, dynamic> fields) async {
    final title = (fields['title'] as String?)?.trim() ?? '';
    final due = (fields['due_date'] as String?)?.trim() ?? '';
    final desc = (fields['description'] as String?)?.trim() ?? '';
    return Followup(
      id: 'F${DateTime.now().millisecondsSinceEpoch.remainder(100000)}',
      kind: fields['task_type'] as String? ?? 'Call',
      contact: title,
      custId: null,
      leadId: null,
      company: title,
      due: due.isEmpty ? '09 Jul 2026' : due,
      time: '10:00',
      status: 'due',
      owner: 'me',
      title: 'Follow-up',
      description: desc,
    );
  }

  /// No-op — mock mode persists status flips via the session override provider.
  /// Mock mode has no schema, so the sheet never takes the schema-driven path
  /// and never calls this.
  @override
  Future<Followup?> createFollowupFields(Map<String, dynamic> fields) async => null;

  @override
  Future<void> setFollowupDone(String id, bool done) async {}
}
