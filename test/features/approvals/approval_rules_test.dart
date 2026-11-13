// Unified Approvals — the pure rules ported from the webapp's `approval.ts`
// and `approvalView.ts`.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/app/router/routes.dart';
import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/approvals/application/approval_rules.dart';
import 'package:clozrapp/features/approvals/domain/entities/approval.dart';

void main() {
  group('closeNeedsApproval', () {
    const gates = ApprovalGates(close: true, closeStatuses: ['won', 'lost']);

    test('only a gated status type needs approval', () {
      expect(closeNeedsApproval(gates, 'won'), isTrue);
      expect(closeNeedsApproval(gates, 'LOST'), isTrue);
      expect(closeNeedsApproval(gates, 'junk'), isFalse);
      expect(closeNeedsApproval(gates, null), isFalse);
      expect(closeNeedsApproval(gates, ''), isFalse);
    });

    test('a gate that is off never asks', () {
      expect(
          closeNeedsApproval(
              const ApprovalGates(closeStatuses: ['won']), 'won'),
          isFalse);
      expect(closeNeedsApproval(ApprovalGates.none, 'completed'), isFalse);
    });

    test('per-module codes: resolved, closed, cancelled', () {
      expect(
          closeNeedsApproval(
              const ApprovalGates(close: true, closeStatuses: ['resolved']),
              'resolved'),
          isTrue);
      const pt = ApprovalGates(close: true, closeStatuses: ['closed']);
      expect(closeNeedsApproval(pt, 'closed'), isTrue);
      // Cancelled only when the org included it.
      expect(closeNeedsApproval(pt, 'cancelled'), isFalse);
    });
  });

  test('a rejection needs at least 10 characters, whitespace aside', () {
    expect(isRejectionNoteValid('too short'), isFalse); // 9
    expect(isRejectionNoteValid('ten chars!'), isTrue); // 10
    expect(isRejectionNoteValid('   short    '), isFalse);
    expect(rejectionNoteMin, 10);
    expect(approvalNoteMax, 2000);
    expect(bulkDecideMax, 200);
  });

  test('narrowing filters drive the empty copy', () {
    expect(hasNarrowingFilters(const ApprovalListQuery()), isFalse);
    expect(
        hasNarrowingFilters(const ApprovalListQuery(
            tab: ApprovalTabs.team, scope: ApprovalScopes.all)),
        isFalse);
    expect(
        hasNarrowingFilters(const ApprovalListQuery(
            tab: ApprovalTabs.team, scope: ApprovalScopes.direct)),
        isTrue);
    expect(hasNarrowingFilters(const ApprovalListQuery(kind: 'due_date')),
        isTrue);
    expect(hasNarrowingFilters(const ApprovalListQuery(search: ' acme ')),
        isTrue);
    expect(hasNarrowingFilters(const ApprovalListQuery(search: '   ')),
        isFalse);
  });

  group('list params', () {
    test('a tab sends only what it supports', () {
      final pending = approvalListParams(const ApprovalListQuery(
          status: 'approved', scope: 'direct', requesterId: 'u1'));
      expect(pending['tab'], 'pending');
      expect(pending.containsKey('status'), isFalse);
      expect(pending.containsKey('scope'), isFalse);
      expect(pending['requester'], 'u1');

      final mine = approvalListParams(const ApprovalListQuery(
          tab: ApprovalTabs.mine, requesterId: 'u1', status: 'approved'));
      expect(mine.containsKey('requester'), isFalse);
      expect(mine['status'], 'approved');

      final team = approvalListParams(
          const ApprovalListQuery(tab: ApprovalTabs.team, scope: 'indirect'));
      expect(team['scope'], 'indirect');
    });

    test('dates cover whole days; page size is capped', () {
      final p = approvalListParams(ApprovalListQuery(
        createdAfter: DateTime(2026, 11, 1, 15, 30),
        createdBefore: DateTime(2026, 11, 3, 8),
        pageSize: 500,
        search: '  acme ',
      ));
      expect(p['created_after'], startsWith('2026-11-01T00:00:00'));
      expect(p['created_before'], startsWith('2026-11-03T23:59:59'));
      expect(p['page_size'], 200);
      expect(p['search'], 'acme');
      expect(p['page'], 1);
    });
  });

  test('Team tab: managers and admins always, others once it has rows', () {
    expect(showTeamTab(manages: true, isAdmin: false, teamCount: 0), isTrue);
    expect(showTeamTab(manages: false, isAdmin: true, teamCount: 0), isTrue);
    expect(showTeamTab(manages: false, isAdmin: false, teamCount: 0), isFalse);
    expect(showTeamTab(manages: false, isAdmin: false, teamCount: 2), isTrue);
  });

  test('labels and fallbacks', () {
    expect(moduleKindLine('task', 'close'), 'Task · Closing');
    expect(moduleKindLine('issue', 'owner_transfer'), 'Ticket · Owner transfer');
    expect(moduleKindLine('weird', ''), 'Record');
    expect(statusLabel('superseded'), 'Superseded');
    expect(statusLabel('on_hold'), 'On hold');
    expect(changeLabel('In progress', 'Completed'), 'In progress → Completed');
    expect(changeLabel('', 'Completed'), '— → Completed');
    expect(changeLabel('', ''), '');
    expect(summaryLabel('due_date'), 'Due date');
  });

  test('every module opens its own record page', () {
    expect(approvalRecordPath('lead', 'l1'), '${Routes.leadDetail}?id=l1');
    expect(approvalRecordPath('task', 't1'), '${Routes.taskDetail}?id=t1');
    expect(approvalRecordPath('followup', 'f1'),
        '${Routes.followupDetail}?id=f1');
    expect(approvalRecordPath('issue', 'i1'), '${Routes.ticketDetail}?id=i1');
    expect(approvalRecordPath('project_task', 'p1'),
        '${Routes.opsTaskDetail}?id=p1');
    expect(approvalRecordPath('project', 'p2'),
        '${Routes.projectDetail}?id=p2');
    expect(approvalRecordPath('lead', ''), isNull);
    expect(approvalRecordPath('nope', 'x'), isNull);
  });

  test('the record banner headline', () {
    final p = PendingApproval(
        id: 'a',
        kind: 'close',
        to: 'Completed',
        approverName: 'Priya Nair',
        createdAt: DateTime(2026, 11, 3));
    expect(pendingHeadline(p, date: (_) => '3 Nov 2026'),
        'Closing to Completed is waiting for approval from Priya Nair (since 3 Nov 2026).');
    expect(pendingHeadline(const PendingApproval(id: 'b')),
        'A change is waiting for approval.');
  });

  test('empty copy per tab, and when filters hide everything', () {
    expect(emptyCopy('pending', filtered: false).title,
        'Nothing is waiting for you');
    expect(emptyCopy('mine', filtered: false).title, 'You have no requests');
    expect(emptyCopy('team', filtered: false).title, 'No team requests');
    expect(emptyCopy('history', filtered: false).title,
        'No decided requests yet');
    expect(emptyCopy('pending', filtered: true).title,
        'No requests match your filters');
  });

  test('refusals: the server sentence, stale codes refresh the list', () {
    const stale = AppError(
        type: AppErrorType.conflict,
        message: 'This request is no longer valid: The task is already closed.',
        statusCode: 409,
        code: 'APPROVAL_STALE');
    expect(approvalErrorMessage(stale), stale.message);
    expect(approvalErrorIsStale(stale), isTrue);
    const blank = AppError(
        type: AppErrorType.conflict,
        message: '',
        code: 'ESCALATION_UNAVAILABLE');
    expect(approvalErrorMessage(blank),
        'There is no active manager above you to escalate to.');
    expect(approvalErrorIsStale(blank), isFalse);
  });

  test('bulk outcome label', () {
    expect(bulkResultLabel(const BulkDecisionResult(updated: 3)), '3 done');
    expect(
        bulkResultLabel(
            const BulkDecisionResult(updated: 1, skippedIds: ['a', 'b'])),
        '1 done · 2 skipped');
  });
}
