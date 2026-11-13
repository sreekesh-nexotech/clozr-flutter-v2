import '../../../../core/network/app_error.dart';
import '../../domain/entities/approval.dart';
import '../../domain/repositories/approvals_repository.dart';
import '../data_sources/local/approvals_mock_ds.dart';

/// Mock-backed [ApprovalsRepository] (mock mode). Decisions update the seed in
/// memory so the screens can be exercised without a backend. The API twin is
/// `ApprovalsApiRepository`.
class ApprovalsRepositoryImpl implements ApprovalsRepository {
  ApprovalsRepositoryImpl(ApprovalsMockDataSource local) : _rows = local.rows();

  final List<Map<String, dynamic>> _rows;

  bool _inTab(Map<String, dynamic> r, String tab) {
    final tabs = r['tabs'] as List? ?? const [];
    final pending = r['status'] == ApprovalStatuses.pending;
    return switch (tab) {
      ApprovalTabs.history => !pending,
      ApprovalTabs.pending => pending && tabs.contains(tab),
      _ => tabs.contains(tab),
    };
  }

  @override
  Future<ApprovalPage> list(ApprovalListQuery q) async {
    final search = q.search.trim().toLowerCase();
    final rows = [
      for (final r in _rows)
        if (_inTab(r, q.tab) &&
            (q.kind == null || r['kind'] == q.kind) &&
            (q.module == null || r['module'] == q.module) &&
            (q.status == null ||
                q.tab == ApprovalTabs.pending ||
                r['status'] == q.status) &&
            (search.isEmpty ||
                '${r['record_label']}'.toLowerCase().contains(search)))
          Approval.fromJson(r),
    ];
    return ApprovalPage(
        count: rows.length, rows: rows.take(q.pageSize).toList());
  }

  Map<String, dynamic> _row(String id) => _rows.firstWhere(
        (r) => r['approval_id'] == id,
        orElse: () => throw const AppError(
            type: AppErrorType.notFound,
            message: 'Approval request not found.',
            statusCode: 404),
      );

  @override
  Future<ApprovalDetail> detail(String id) async =>
      ApprovalDetail.fromJson(_row(id));

  @override
  Future<ApprovalCounts> counts() async {
    final pending = [
      for (final r in _rows)
        if (_inTab(r, ApprovalTabs.pending)) r
    ];
    final byKind = <String, int>{for (final k in ApprovalKinds.all) k: 0};
    final byModule = <String, int>{};
    for (final r in pending) {
      byKind['${r['kind']}'] = (byKind['${r['kind']}'] ?? 0) + 1;
      byModule['${r['module']}'] = (byModule['${r['module']}'] ?? 0) + 1;
    }
    return ApprovalCounts(
        pendingForMe: pending.length,
        byKind: byKind,
        byModule: byModule,
        other: const {'quote_discounts': 0, 'rewards': 0, 'lifecycle': 0});
  }

  static const _outcome = {
    'approve': ApprovalStatuses.approved,
    'reject': ApprovalStatuses.rejected,
    'withdraw': ApprovalStatuses.withdrawn,
  };

  @override
  Future<ApprovalDetail> act(String id, String action,
      {String note = ''}) async {
    final r = _row(id);
    if (r['status'] != ApprovalStatuses.pending) {
      throw const AppError(
          type: AppErrorType.conflict,
          message: 'This request is already decided.',
          statusCode: 409,
          code: 'APPROVAL_NOT_PENDING');
    }
    if (action == 'escalate') {
      r['current_approver'] = {
        'user_id': 'u-boss',
        'email': '',
        'full_name': 'Asha Kurian'
      };
      r['route_reason'] = 'escalation';
      r['can_decide'] = false;
      r['can_escalate'] = false;
      r['tabs'] = ['history'];
    } else {
      r['status'] = _outcome[action] ?? r['status'];
      r['decision_note'] = note.trim();
      r['can_decide'] = false;
      r['can_escalate'] = false;
      r['can_withdraw'] = false;
      r['decided_at'] = DateTime.now().toUtc().toIso8601String();
    }
    return ApprovalDetail.fromJson(r);
  }

  @override
  Future<BulkDecisionResult> bulkDecide(List<String> ids, String verdict,
      {String note = ''}) async {
    var updated = 0;
    final skipped = <String>[];
    final errors = <BulkDecisionError>[];
    for (final id in ids) {
      try {
        await act(id, verdict, note: note);
        updated++;
      } on AppError catch (e) {
        skipped.add(id);
        errors.add(
            BulkDecisionError(id: id, code: e.code ?? '', message: e.message));
      }
    }
    return BulkDecisionResult(
        updated: updated, skippedIds: skipped, errors: errors);
  }

  @override
  Future<RecordApprovalState> forRecord(String module, String objectId) async {
    for (final r in _rows) {
      if (r['module'] == module &&
          r['object_id'] == objectId &&
          r['status'] == ApprovalStatuses.pending) {
        return RecordApprovalState(pending: PendingApproval.fromJson(r));
      }
    }
    return const RecordApprovalState();
  }
}
