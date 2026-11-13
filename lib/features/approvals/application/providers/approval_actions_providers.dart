import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../crm/application/providers/crm_tasks_providers.dart';
import '../../../crm/application/providers/followups_providers.dart';
import '../../../crm/application/providers/leads_providers.dart';
import '../../../helpdesk/application/providers/tickets_providers.dart';
import '../../../operations/application/providers/ops_tasks_providers.dart';
import '../../../operations/application/providers/projects_providers.dart';
import '../../domain/entities/approval.dart';
import '../approval_rules.dart';
import 'approvals_providers.dart';

/// The approvals side of any change: lists, details, counts, banners.
void invalidateApprovals(WidgetRef ref) {
  ref.invalidate(approvalsListProvider);
  ref.invalidate(approvalDetailProvider);
  ref.invalidate(approvalCountsProvider);
  ref.invalidate(approvalsTeamProbeProvider);
  ref.invalidate(recordApprovalProvider);
}

/// A decision changes the record, not only the request — re-read the record
/// [module] / [objectId] and the lists that show it (webapp
/// `invalidateApprovalRecord`). An unknown module refreshes every one of them,
/// since the alternative is a page showing the old status.
void invalidateApprovalRecord(WidgetRef ref, String module, String objectId) {
  final all = !ApprovalModules.all.contains(module);
  bool hits(String m) => all || module == m;
  if (hits(ApprovalModules.lead)) {
    if (objectId.isNotEmpty) {
      ref.invalidate(leadDetailProvider(objectId));
      ref.invalidate(leadRowProvider(objectId));
    }
    ref.invalidate(leadsScopedProvider);
  }
  if (hits(ApprovalModules.task) || hits(ApprovalModules.followup)) {
    if (objectId.isNotEmpty) {
      ref.invalidate(taskRowProvider(objectId));
      ref.invalidate(followupRowProvider(objectId));
    }
    ref.invalidate(crmTasksProvider);
    ref.invalidate(followupsScopedProvider);
  }
  if (hits(ApprovalModules.issue)) {
    if (objectId.isNotEmpty) ref.invalidate(ticketDetailProvider(objectId));
    ref.invalidate(ticketsScopedProvider);
  }
  if (hits(ApprovalModules.projectTask)) {
    if (objectId.isNotEmpty) ref.invalidate(opsTaskDetailProvider(objectId));
    ref.invalidate(opsTasksScopedProvider);
  }
  if (hits(ApprovalModules.project)) {
    if (objectId.isNotEmpty) ref.invalidate(projectDetailProvider(objectId));
    ref.invalidate(projectsScopedProvider);
  }
}

/// Runs [action] on the request [id] about [module]/[objectId], then refreshes
/// the approvals and the record. Throws `AppError` (the dialog shows it).
Future<ApprovalDetail> runApprovalAction(
  WidgetRef ref, {
  required String id,
  required String module,
  required String objectId,
  required ApprovalAction action,
  String note = '',
}) async {
  final result = await ref
      .read(approvalsRepositoryProvider)
      .act(id, action.name, note: note);
  // Decided (or withdrawn): the record is no longer waiting on this session.
  if (action != ApprovalAction.escalate && objectId.isNotEmpty) {
    ref.read(heldRecordsProvider.notifier).release(objectId);
  }
  invalidateApprovals(ref);
  invalidateApprovalRecord(ref, module, objectId);
  return result;
}

/// Bulk approve / reject; refreshes everything a decision can touch.
Future<BulkDecisionResult> runBulkDecision(
  WidgetRef ref, {
  required List<Approval> rows,
  required bool approve,
  String note = '',
}) async {
  final result = await ref.read(approvalsRepositoryProvider).bulkDecide(
      [for (final r in rows) r.id], approve ? 'approve' : 'reject',
      note: note);
  final skipped = result.skippedIds.toSet();
  final held = ref.read(heldRecordsProvider.notifier);
  invalidateApprovals(ref);
  for (final r in rows) {
    if (skipped.contains(r.id)) continue;
    held.release(r.objectId);
    invalidateApprovalRecord(ref, r.module, r.objectId);
  }
  return result;
}
