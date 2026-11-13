// Unified Approvals — the row / detail / counts / record-state mappers, fed
// the shapes `docs/backend/approvals.md` documents (and sparse / unknown
// variants, which must render rather than throw).
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/approvals/domain/entities/approval.dart';

Map<String, dynamic> _user(String id, String name) =>
    {'user_id': id, 'email': '$id@acme.com', 'full_name': name};

Map<String, dynamic> _row({Map<String, dynamic> extra = const {}}) => {
      'approval_id': 'c41d',
      'module': 'task',
      'kind': 'close',
      'object_id': '9f2e',
      'record_label': 'Send proposal to Acme',
      'project_id': null,
      'can_decide': true,
      'requested_by': _user('u1', 'Ravi Menon'),
      'record_owner': _user('u1', 'Ravi Menon'),
      'current_approver': _user('u2', 'Priya Nair'),
      'route_reason': 'owner_manager',
      'display': {'from': 'In progress', 'to': 'Completed'},
      'request_note': 'Customer confirmed by phone',
      'status': 'pending',
      'decision_source': '',
      'decided_by': null,
      'decided_at': null,
      'decision_note': '',
      'created_at': '2026-11-03T09:12:44Z',
      'updated_at': '2026-11-03T09:12:44Z',
      ...extra,
    };

void main() {
  test('a list row maps every documented field', () {
    final a = Approval.fromJson(_row());
    expect(a.id, 'c41d');
    expect(a.module, 'task');
    expect(a.kind, 'close');
    expect(a.objectId, '9f2e');
    expect(a.recordLabel, 'Send proposal to Acme');
    expect(a.canDecide, isTrue);
    expect(a.isPending, isTrue);
    expect(a.requestedBy?.name, 'Ravi Menon');
    expect(a.currentApprover?.id, 'u2');
    expect(a.from, 'In progress');
    expect(a.to, 'Completed');
    expect(a.requestNote, 'Customer confirmed by phone');
    expect(a.decidedBy, isNull);
    expect(a.createdAt, isNotNull);
    expect(a.projectId, '');
  });

  test('unknown enums and missing people do not throw', () {
    final a = Approval.fromJson({
      'approval_id': 'x',
      'module': 'something_new',
      'kind': 'mystery',
      'status': 'paused',
      'record_owner': null,
      'display': 'not a map',
    });
    expect(a.module, 'something_new');
    expect(a.status, 'paused');
    expect(a.recordOwner, isNull);
    expect(a.from, '');
    // A blank status reads as pending, the only state a row can start in.
    expect(Approval.fromJson({'approval_id': 'y'}).status, 'pending');
  });

  test('a user falls back to the email when the name is blank', () {
    final u = ApprovalUser.fromJson({'user_id': 'u', 'email': 'a@b.c', 'full_name': ''});
    expect(u?.name, 'a@b.c');
    expect(ApprovalUser.fromJson(null), isNull);
    expect(ApprovalUser.fromJson({'user_id': '', 'full_name': ''}), isNull);
  });

  test('a detail row carries steps, verbs and an ordered record summary', () {
    final d = ApprovalDetail.fromJson(_row(extra: {
      'payload': {'status_id': 's'},
      'steps': [
        {
          'step_id': 's1',
          'approver': _user('u2', 'Priya Nair'),
          'reason': 'owner_manager',
          'outcome': '',
          'note': '',
          'assigned_at': '2026-11-03T09:12:44Z',
          'acted_at': null,
        },
        'junk',
      ],
      'can_escalate': true,
      'can_withdraw': false,
      'record_summary': {
        'label': 'Send proposal to Acme',
        'status': 'In progress',
        'owner': 'Ravi Menon',
        'empty': '',
        'nested': {'a': 1},
        'due_date': '2026-11-10',
      },
      'record_visible': true,
    }));
    expect(d.approval.id, 'c41d');
    expect(d.steps, hasLength(1));
    expect(d.steps.single.approver?.name, 'Priya Nair');
    expect(d.steps.single.outcome, '');
    expect(d.canEscalate, isTrue);
    expect(d.canWithdraw, isFalse);
    expect(d.recordVisible, isTrue);
    expect([for (final (k, _) in d.summary) k],
        ['label', 'status', 'owner', 'due_date']);
  });

  test('counts read every block and default to zero', () {
    final c = ApprovalCounts.fromJson({
      'pending_for_me': 4,
      'by_kind': {'close': 3, 'owner_transfer': 0, 'due_date': 1},
      'by_module': {'task': 3, 'project_task': 1},
      'other': {'quote_discounts': 1, 'rewards': 0, 'lifecycle': 0},
    });
    expect(c.pendingForMe, 4);
    expect(c.byKind['due_date'], 1);
    expect(c.byModule['project_task'], 1);
    expect(c.other['quote_discounts'], 1);
    expect(ApprovalCounts.fromJson(null), ApprovalCounts.zero);
  });

  test('record state: pending request, gates, and an older payload', () {
    final s = RecordApprovalState.fromJson({
      'pending_approval': {
        'approval_id': 'c41d',
        'kind': 'close',
        'status': 'pending',
        'current_approver': {'user_id': 'u2', 'full_name': 'Priya Nair'},
        'display': {'from': 'In progress', 'to': 'Completed'},
        'created_at': '2026-11-03T09:12:44+00:00',
        'can_decide': false,
        'can_escalate': false,
        'can_withdraw': true,
      },
      'approval_gates': {
        'close': true,
        'owner_transfer': false,
        'close_statuses': ['Completed'],
      },
    });
    expect(s.known, isTrue);
    expect(s.pending?.approverName, 'Priya Nair');
    expect(s.pending?.canWithdraw, isTrue);
    expect(s.gates.close, isTrue);
    expect(s.gates.closeStatuses, ['completed']);

    final none = RecordApprovalState.fromJson(
        {'pending_approval': null, 'approval_gates': null});
    expect(none.known, isTrue);
    expect(none.pending, isNull);
    expect(none.gates, ApprovalGates.none);

    expect(RecordApprovalState.fromJson({'name': 'x'}).known, isFalse);
  });

  test('a decided pending_approval is not shown as waiting', () {
    expect(
        PendingApproval.fromJson({'approval_id': 'a', 'status': 'approved'}),
        isNull);
  });

  test('bulk result: updated, skipped and per-row errors', () {
    final r = BulkDecisionResult.fromJson({
      'updated': 1,
      'skipped_ids': ['8a02'],
      'errors': [
        {
          'id': '8a02',
          'code': 'APPROVAL_NOT_PENDING',
          'message': 'This request is already approved.'
        }
      ],
    });
    expect(r.updated, 1);
    expect(r.skippedIds, ['8a02']);
    expect(r.errors.single.code, 'APPROVAL_NOT_PENDING');
  });
}
