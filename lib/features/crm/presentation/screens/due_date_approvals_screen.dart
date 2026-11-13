import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../approvals/application/providers/approvals_providers.dart';
import '../../../approvals/domain/entities/approval.dart';

export '../../../approvals/application/providers/approvals_providers.dart'
    show approvalCountsProvider;

// Due-date approvals moved into Unified Approvals (route map Phase 8): the
// old `/sla/due-date-changes/*` endpoints are deprecated, and
// `Routes.dueDateApprovals` now redirects to `/approvals?kind=due_date`.
// Only the toolbar count stays here, for the Tasks / Follow-ups / Operations
// toolbars that already import it.

/// The Tasks toolbar's "Due date approvals (N)": due-date requests waiting
/// for this user, from `GET /approvals/counts/`; 0 on any failure.
final pendingDueDateCountProvider = Provider.autoDispose<int>((ref) =>
    ref
        .watch(approvalCountsProvider)
        .valueOrNull
        ?.byKind[ApprovalKinds.dueDate] ??
    0);
