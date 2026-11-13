import '../../../app/router/routes.dart';
import '../../../core/network/app_error.dart';
import '../domain/entities/approval.dart';

// Pure rules and copy for Unified Approvals — the webapp's `approval.ts` and
// `approvalView.ts`. Kept free of widgets so every rule is unit-testable.

/// A rejection needs a reason of at least this many characters.
const int rejectionNoteMin = 10;

/// Every approval comment is capped here.
const int approvalNoteMax = 2000;

/// `bulk-decide` takes at most this many ids per call.
const int bulkDecideMax = 200;

/// Rejecting needs a real reason; approving and escalating don't.
bool isRejectionNoteValid(String note) =>
    note.trim().length >= rejectionNoteMin;

/// Whether moving to a status of type [statusCode] would wait for approval
/// from the current user — the code must be one of the gate's
/// `close_statuses` (`resolved` for a ticket, `closed` for a project, …).
bool closeNeedsApproval(ApprovalGates gates, String? statusCode) {
  final code = (statusCode ?? '').trim().toLowerCase();
  return gates.close && code.isNotEmpty && gates.closeStatuses.contains(code);
}

/// Whether a query narrows the tab beyond its default — picks the empty copy.
bool hasNarrowingFilters(ApprovalListQuery q) =>
    q.kind != null ||
    q.module != null ||
    q.status != null ||
    (q.scope != null && q.scope != ApprovalScopes.all) ||
    (q.requesterId ?? '').isNotEmpty ||
    (q.ownerId ?? '').isNotEmpty ||
    (q.projectId ?? '').isNotEmpty ||
    q.createdAfter != null ||
    q.createdBefore != null ||
    q.search.trim().isNotEmpty;

/// The Team tab is offered to managers and System Admins; anyone else (a
/// Project Manager has no flag of their own) sees it once it has rows.
bool showTeamTab(
        {required bool manages,
        required bool isAdmin,
        required int teamCount}) =>
    manages || isAdmin || teamCount > 0;

/// The `GET /approvals/` query string for [q].
Map<String, dynamic> approvalListParams(ApprovalListQuery q) {
  String iso(DateTime d) => d.toIso8601String();
  final after = q.createdAfter;
  final before = q.createdBefore;
  return {
    'tab': q.tab,
    if (q.kind != null) 'kind': q.kind,
    if (q.module != null) 'module': q.module,
    // Waiting-for-me lists pending rows only.
    if (q.status != null && q.tab != ApprovalTabs.pending) 'status': q.status,
    if (q.tab == ApprovalTabs.team && q.scope != null) 'scope': q.scope,
    // "My requests" only lists the viewer's own.
    if ((q.requesterId ?? '').isNotEmpty && q.tab != ApprovalTabs.mine)
      'requester': q.requesterId,
    if ((q.ownerId ?? '').isNotEmpty) 'owner': q.ownerId,
    if ((q.projectId ?? '').isNotEmpty) 'project': q.projectId,
    if (after != null)
      'created_after': iso(DateTime(after.year, after.month, after.day)),
    if (before != null)
      'created_before':
          iso(DateTime(before.year, before.month, before.day, 23, 59, 59)),
    if (q.search.trim().isNotEmpty) 'search': q.search.trim(),
    'page': q.page,
    'page_size': q.pageSize.clamp(1, bulkDecideMax),
  };
}

const Map<String, String> approvalTabLabels = {
  ApprovalTabs.pending: 'Waiting for me',
  ApprovalTabs.mine: 'My requests',
  ApprovalTabs.team: 'Team',
  ApprovalTabs.history: 'History',
};

const Map<String, String> approvalKindLabels = {
  ApprovalKinds.close: 'Closing',
  ApprovalKinds.ownerTransfer: 'Owner transfer',
  ApprovalKinds.dueDate: 'Due-date change',
};

const Map<String, String> approvalModuleLabels = {
  ApprovalModules.lead: 'Lead',
  ApprovalModules.task: 'Task',
  ApprovalModules.followup: 'Follow-up',
  ApprovalModules.issue: 'Ticket',
  ApprovalModules.projectTask: 'Project task',
  ApprovalModules.project: 'Project',
};

const Map<String, String> approvalScopeLabels = {
  ApprovalScopes.all: 'All reportees',
  ApprovalScopes.direct: 'Direct reportees',
  ApprovalScopes.indirect: 'Reportees of reportees',
};

const Map<String, String> approvalStatusLabels = {
  ApprovalStatuses.pending: 'Pending',
  ApprovalStatuses.approved: 'Approved',
  ApprovalStatuses.rejected: 'Rejected',
  ApprovalStatuses.withdrawn: 'Withdrawn',
  ApprovalStatuses.superseded: 'Superseded',
};

/// Why a request sits with this approver (`route_reason`).
const Map<String, String> routeReasonLabels = {
  'owner_manager': "Owner's manager",
  'project_manager': 'Project manager',
  'next_active': 'Next active manager',
  'system_admin': 'System admin',
  'escalation': 'Escalated',
  'reroute': 'Rerouted',
};

const Map<String, String> stepOutcomeLabels = {
  'approved': 'Approved',
  'rejected': 'Rejected',
  'escalated': 'Escalated',
  'rerouted': 'Rerouted',
  'superseded': 'Superseded',
  'withdrawn': 'Withdrawn',
};

String moduleLabel(String module) => approvalModuleLabels[module] ?? 'Record';

String kindLabel(String kind) => approvalKindLabels[kind] ?? '';

String statusLabel(String status) {
  final known = approvalStatusLabels[status];
  if (known != null) return known;
  if (status.isEmpty) return '';
  return status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
}

/// "Task · Closing".
String moduleKindLine(String module, String kind) {
  final k = kindLabel(kind);
  return k.isEmpty ? moduleLabel(module) : '${moduleLabel(module)} · $k';
}

/// "In progress → Completed"; empty when neither side is known.
String changeLabel(String from, String to) => from.isEmpty && to.isEmpty
    ? ''
    : '${from.isEmpty ? '—' : from} → ${to.isEmpty ? '—' : to}';

/// `record_summary` keys vary by module: "due_date" reads as "Due date".
String summaryLabel(String key) {
  final words = key.replaceAll('_', ' ').trim();
  if (words.isEmpty) return '';
  return words[0].toUpperCase() + words.substring(1);
}

/// The record page an approval is about, or null when there is none to open.
String? approvalRecordPath(String module, String objectId) {
  if (objectId.isEmpty) return null;
  final base = switch (module) {
    ApprovalModules.lead => Routes.leadDetail,
    ApprovalModules.task => Routes.taskDetail,
    ApprovalModules.followup => Routes.followupDetail,
    ApprovalModules.issue => Routes.ticketDetail,
    ApprovalModules.projectTask => Routes.opsTaskDetail,
    ApprovalModules.project => Routes.projectDetail,
    _ => null,
  };
  return base == null ? null : '$base?id=${Uri.encodeQueryComponent(objectId)}';
}

/// What a record banner says while a request waits.
String pendingHeadline(PendingApproval p, {String Function(DateTime)? date}) {
  final phrase = switch (p.kind) {
    ApprovalKinds.close => 'Closing to',
    ApprovalKinds.ownerTransfer => 'Owner transfer to',
    ApprovalKinds.dueDate => 'Due-date change to',
    _ => null,
  };
  final what =
      phrase == null ? 'A change' : '$phrase ${p.to.isEmpty ? '—' : p.to}';
  final who = p.approverName.isEmpty ? '' : ' from ${p.approverName}';
  final created = p.createdAt;
  final since =
      created == null || date == null ? '' : ' (since ${date(created)})';
  return '$what is waiting for approval$who$since.';
}

/// Empty-list copy per tab, and the variant when filters hide everything.
({String title, String body}) emptyCopy(String tab, {required bool filtered}) {
  if (filtered) {
    return (
      title: 'No requests match your filters',
      body: 'Try removing a filter to see more.'
    );
  }
  return switch (tab) {
    ApprovalTabs.mine => (
        title: 'You have no requests',
        body:
            'Closing a record, changing its owner or moving a due date can need approval. Those requests show up here.'
      ),
    ApprovalTabs.team => (
        title: 'No team requests',
        body: 'Requests on records owned by people below you show up here.'
      ),
    ApprovalTabs.history => (
        title: 'No decided requests yet',
        body:
            'Requests you raised, decided or escalated show up here once they are closed.'
      ),
    _ => (
        title: 'Nothing is waiting for you',
        body: 'Requests routed to you show up here until you decide them.'
      ),
  };
}

/// The verbs a viewer may use on a request.
enum ApprovalAction { approve, reject, escalate, withdraw }

const Map<ApprovalAction, String> approvalDoneToast = {
  ApprovalAction.approve: 'Approved',
  ApprovalAction.reject: 'Rejected',
  ApprovalAction.escalate: 'Escalated',
  ApprovalAction.withdraw: 'Request withdrawn',
};

/// The server's sentence for a refused action — it is already user-facing
/// (`detail`), so only the bare fallbacks get our own words.
String approvalErrorMessage(AppError e) {
  if (e.message.trim().isNotEmpty) return e.message;
  return switch (e.code) {
    'APPROVAL_NOT_PENDING' => 'This request has already been decided.',
    'APPROVAL_STALE' => 'This request no longer applies.',
    'APPROVAL_NOT_APPROVER' => 'You are not the approver of this request.',
    'REJECTION_REASON_REQUIRED' =>
      'A rejection reason of at least $rejectionNoteMin characters is required.',
    'ESCALATION_UNAVAILABLE' =>
      'There is no active manager above you to escalate to.',
    _ => 'Something went wrong. Please try again.',
  };
}

/// Whether a refusal means the list is out of date (refresh it).
bool approvalErrorIsStale(AppError e) =>
    e.code == 'APPROVAL_STALE' || e.code == 'APPROVAL_NOT_PENDING';

/// "3 done · 1 skipped".
String bulkResultLabel(BulkDecisionResult r) {
  final skipped = r.skippedIds.length;
  return '${r.updated} done${skipped > 0 ? ' · $skipped skipped' : ''}';
}
