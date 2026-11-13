import '../entities/approval.dart';

/// Unified Approvals contract. Mock vs REST is an infrastructure detail; every
/// method throws `AppError` on failure.
abstract class ApprovalsRepository {
  Future<ApprovalPage> list(ApprovalListQuery query);

  Future<ApprovalDetail> detail(String id);

  Future<ApprovalCounts> counts();

  /// `approve` / `reject` / `escalate` take an optional [note] (a rejection
  /// needs one of at least 10 characters); `withdraw` sends none.
  Future<ApprovalDetail> act(String id, String action, {String note = ''});

  /// `verdict` is `approve` or `reject`.
  Future<BulkDecisionResult> bulkDecide(List<String> ids, String verdict,
      {String note = ''});

  /// A record's pending request and gates.
  Future<RecordApprovalState> forRecord(String module, String objectId);
}
