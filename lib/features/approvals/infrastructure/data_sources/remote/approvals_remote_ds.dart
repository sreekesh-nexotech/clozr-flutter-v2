import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../application/approval_rules.dart';
import '../../../domain/entities/approval.dart';

/// `/api/v1/approvals/…` over the shared [ApiService].
class ApprovalsRemoteDataSource {
  ApprovalsRemoteDataSource(this._api);

  final ApiService _api;

  static Map<String, dynamic> _map(Object? body) =>
      body is Map ? Map<String, dynamic>.from(body) : const {};

  Future<ApprovalPage> list(ApprovalListQuery query) async {
    final body = await _api.get(ApiEndpoints.approvals,
        query: approvalListParams(query));
    final m = _map(body);
    final raw = body is List ? body : m['results'];
    final rows = [
      if (raw is List)
        for (final r in raw)
          if (r is Map) Approval.fromJson(Map<String, dynamic>.from(r)),
    ];
    return ApprovalPage(
        count: (m['count'] as num?)?.toInt() ?? rows.length, rows: rows);
  }

  Future<ApprovalDetail> detail(String id) async =>
      ApprovalDetail.fromJson(_map(await _api.get(ApiEndpoints.approval(id))));

  /// Best-effort: the badge and the strip read it, and both fall back to
  /// nothing, so a refusal is kept off the shell's failure toast.
  Future<ApprovalCounts> counts() async => ApprovalCounts.fromJson(
      await _api.get(ApiEndpoints.approvalCounts, quiet: true));

  Future<ApprovalDetail> act(String id, String action,
      {String note = ''}) async {
    final trimmed = note.trim();
    final body = action == 'withdraw'
        ? null
        : <String, dynamic>{if (trimmed.isNotEmpty) 'note': trimmed};
    return ApprovalDetail.fromJson(_map(
        await _api.post(ApiEndpoints.approvalAction(id, action), body: body)));
  }

  Future<BulkDecisionResult> bulkDecide(List<String> ids, String verdict,
      {String note = ''}) async {
    final trimmed = note.trim();
    return BulkDecisionResult.fromJson(
        await _api.post(ApiEndpoints.approvalBulkDecide, body: {
      'ids': ids,
      'verdict': verdict,
      if (trimmed.isNotEmpty) 'note': trimmed,
    }));
  }

  Future<RecordApprovalState> forRecord(String module, String objectId) async {
    final body = await _api.get(ApiEndpoints.approvalForRecord,
        query: {'module': module, 'object_id': objectId}, quiet: true);
    final state = RecordApprovalState.fromJson(body);
    // The endpoint always answers both keys; an empty one still counts.
    return RecordApprovalState(pending: state.pending, gates: state.gates);
  }
}
