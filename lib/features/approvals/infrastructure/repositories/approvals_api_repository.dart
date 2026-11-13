import '../../domain/entities/approval.dart';
import '../../domain/repositories/approvals_repository.dart';
import '../data_sources/remote/approvals_remote_ds.dart';

/// API-backed [ApprovalsRepository]. No caching: approval state is the
/// server's answer at the moment, and a stale copy offers a decision that
/// would only come back `APPROVAL_NOT_PENDING`.
class ApprovalsApiRepository implements ApprovalsRepository {
  ApprovalsApiRepository(this._remote);

  final ApprovalsRemoteDataSource _remote;

  @override
  Future<ApprovalPage> list(ApprovalListQuery query) => _remote.list(query);

  @override
  Future<ApprovalDetail> detail(String id) => _remote.detail(id);

  @override
  Future<ApprovalCounts> counts() => _remote.counts();

  @override
  Future<ApprovalDetail> act(String id, String action, {String note = ''}) =>
      _remote.act(id, action, note: note);

  @override
  Future<BulkDecisionResult> bulkDecide(List<String> ids, String verdict,
          {String note = ''}) =>
      _remote.bulkDecide(ids, verdict, note: note);

  @override
  Future<RecordApprovalState> forRecord(String module, String objectId) =>
      _remote.forRecord(module, objectId);
}
