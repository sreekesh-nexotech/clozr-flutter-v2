// Unified Approvals — the 202 interpreter the network layer runs on every
// response (webapp `approvalHold.ts`).
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/approval_hold.dart';

Map<String, dynamic> _envelope({Object? record = const {'task_id': 't1'}}) => {
      'detail': 'Sent to Priya Nair for approval.',
      'code': 'APPROVAL_REQUIRED',
      'approval': {
        'approval_id': 'c41d',
        'object_id': 't1',
        'current_approver': {'user_id': 'u2', 'full_name': 'Priya Nair'},
        'display': {'from': 'In progress', 'to': 'Completed'},
      },
      'applied_fields': ['description'],
      if (record != null) 'record': record,
    };

void main() {
  test('a held save is read from its envelope', () {
    final hold = readApprovalHold(202, _envelope());
    expect(hold, isNotNull);
    expect(hold!.approvalId, 'c41d');
    expect(hold.objectId, 't1');
    expect(hold.message, 'Sent to Priya Nair for approval.');
    expect(hold.approverName, 'Priya Nair');
    expect(hold.to, 'Completed');
    expect(hold.appliedFields, ['description']);
    expect(hold.isEnvelope, isTrue);
    expect(hold.heldIds, ['t1']);
  });

  test('only a 202 with APPROVAL_REQUIRED is a hold', () {
    expect(readApprovalHold(200, _envelope()), isNull);
    expect(readApprovalHold(202, {'code': 'SOMETHING_ELSE'}), isNull);
    expect(readApprovalHold(202, {'code': 'APPROVAL_REQUIRED'}), isNull);
    expect(readApprovalHold(202, 'text'), isNull);
    // A due-date 202 has no envelope.
    expect(
        readApprovalHold(202, {
          'task_id': 't1',
          'pending_due_date_change': {'object_id': 't1'}
        }),
        isNull);
  });

  test('a blank detail falls back to the generic sentence', () {
    final hold = readApprovalHold(202, {..._envelope(), 'detail': ''});
    expect(hold?.message, 'Sent for approval.');
  });

  test('callers reading the answer as the record get the record', () {
    expect(recordOf(202, _envelope()), {'task_id': 't1'});
    // No record in the envelope (a lead conversion): the envelope itself.
    final convert = _envelope(record: null);
    expect(recordOf(202, convert), same(convert));
    final plain = {'task_id': 't1'};
    expect(recordOf(200, plain), same(plain));
    expect(recordOf(202, plain), same(plain));
  });

  test('bulk and due-date answers name the records that went for approval', () {
    expect(
        readPendingIds(202, {
          'success': true,
          'updated': 3,
          'pending': 2,
          'pending_ids': ['a', 'b', ''],
        }),
        ['a', 'b']);
    expect(
        readPendingIds(202, {
          'task_id': 't1',
          'pending_due_date_change': {'object_id': 't1'}
        }),
        ['t1']);
    expect(readPendingIds(200, {'pending_ids': ['a']}), isEmpty);
    expect(readPendingIds(202, {'task_id': 't1'}), isEmpty);
  });

  test('approvalEventOf: one event for any approval answer, else null', () {
    expect(approvalEventOf(202, _envelope())?.isEnvelope, isTrue);
    final bulk = approvalEventOf(202, {'pending_ids': ['a']});
    expect(bulk?.isEnvelope, isFalse);
    expect(bulk?.heldIds, ['a']);
    expect(approvalEventOf(202, {'task_id': 't1'}), isNull);
    expect(approvalEventOf(201, _envelope()), isNull);
  });
}
