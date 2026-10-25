import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/quote_discount_approval_rules.dart';

void main() {
  group('pctLabel', () {
    test('formats like the webapp', () {
      expect(pctLabel('20.00'), '20%');
      expect(pctLabel('12.50'), '12.5%');
      expect(pctLabel('10'), '10%');
      expect(pctLabel(null), '—');
      expect(pctLabel(''), '—');
    });
  });

  group('gating', () {
    test('pending blocks send and accept', () {
      final q = {'approval_status': 'PENDING'};
      expect(isSendBlockedByApproval(q), isTrue);
      expect(markSentBlockedReason(q), 'Waiting for discount approval — it can be marked as sent once approved');
      expect(acceptBlockedByApprovalReason(q), 'The discount needs approval before this quote can be accepted.');
      expect(approvalChipLabel(q), 'PENDING APPROVAL');
    });

    test('rejected blocks send', () {
      final q = {'approval_status': 'REJECTED'};
      expect(markSentBlockedReason(q), 'The discount was not approved — reduce it before marking the quote as sent');
      expect(approvalChipLabel(q), 'APPROVAL REJECTED');
    });

    test('approved / not required / unknown do not block', () {
      for (final s in ['APPROVED', 'NOT_REQUIRED', 'weird', null]) {
        final q = {'approval_status': s};
        expect(isSendBlockedByApproval(q), isFalse);
        expect(markSentBlockedReason(q), '');
        expect(acceptBlockedByApprovalReason(q), '');
      }
      expect(approvalChipLabel({'approval_status': 'APPROVED'}), 'APPROVED');
      expect(approvalChipLabel({'approval_status': 'NOT_REQUIRED'}), isNull);
      expect(markSentBlockedReason(null), '');
    });

    test('server acceptance_block wins', () {
      final q = {
        'approval_status': 'PENDING',
        'acceptance_block': {'code': 'QUOTE_NOT_SENT', 'detail': 'Mark this quote as Sent before accepting it.'},
      };
      expect(acceptBlockedReason(q), 'Mark this quote as Sent before accepting it.');
      expect(acceptBlockedReason({'approval_status': 'PENDING'}), kAcceptNeedsApproval);
    });
  });

  group('DiscountApproval', () {
    Map<String, dynamic> row({String status = 'pending', bool canDecide = true}) => {
          'approval_id': 'a1',
          'quotation': 'uuid-1',
          'quotation_number': 'QTN-00031',
          'quotation_title': 'Acme rollout',
          'status': status.toUpperCase(),
          'discount_pct': '20.00',
          'limit_pct': '10.00',
          'review_comment': status == 'pending' ? null : 'Keep it within 10%',
          'requested_by': {'user_id': 'u1', 'full_name': 'Neeraja Pradeep', 'email': 'n@x'},
          'reviewed_by': status == 'pending' ? null : {'full_name': '', 'email': 'cijo.g@nexotech.cc'},
          'requested_at': '2026-10-20T10:00:00Z',
          'can_decide': canDecide,
        };

    test('maps a pending row', () {
      final a = DiscountApproval.fromJson(row());
      expect(a.quotationId, 'uuid-1');
      expect(a.quotationNumber, 'QTN-00031');
      expect(a.headline, 'Acme rollout');
      expect(a.status, 'pending');
      expect(a.statusLabel, 'Pending');
      expect(pctLabel(a.discountPct), '20%');
      expect(pctLabel(a.limitPct), '10%');
      expect(a.requestedByName, 'Neeraja Pradeep');
      expect(a.showDecide, isTrue);
      expect(a.reviewLine, '');
    });

    test('decided row: review line, no decide', () {
      final a = DiscountApproval.fromJson(row(status: 'rejected'));
      expect(a.showDecide, isFalse);
      expect(a.reviewLine, 'cijo.g@nexotech.cc: “Keep it within 10%”');
    });

    test('page + badge count only decidable pending rows', () {
      final page = discountApprovalPage({
        'count': 3,
        'results': [row(), row(canDecide: false), row()],
      });
      expect(page.count, 3);
      expect(decidableCount(page.rows), 2);
      expect(discountApprovalsLabel(2), 'Discount approvals — 2 waiting for you');
      expect(discountApprovalsLabel(0), 'Discount approvals');
      expect(discountApprovalPage(null).rows, isEmpty);
    });

    test('empty states', () {
      expect(discountApprovalsEmpty('pending').title, 'Nothing waiting for approval');
      expect(discountApprovalsEmpty('pending').body,
          'Quotes whose discount is above the creator’s limit show up here until someone up the reporting line decides.');
      expect(discountApprovalsEmpty('approved').title, 'No approved requests');
      expect(discountApprovalsEmpty('rejected').body, isNull);
    });

    test('decision dialog copy', () {
      expect(discountDecisionBody(approve: true, discountPct: '20.00', limitPct: '10.00'),
          ' has a 20% discount, above the requester’s 10% limit. Once approved it can be marked as sent.');
      expect(discountDecisionBody(approve: false, discountPct: '20.00', limitPct: null),
          ' has a 20% discount. It stays blocked from being sent until the discount is reduced.');
    });
  });

  group('banner facts', () {
    String date(String s) => '20 Oct 2026';

    test('pending banner from the quote record', () {
      final q = {
        'quotation_id': 'uuid-1',
        'approval_status': 'PENDING',
        'discount_pct': '20.00',
        'pending_discount_approval': {
          'approval_id': 'a1',
          'discount_pct': '20.00',
          'limit_pct': '10.00',
          'requested_by': {'full_name': 'Neeraja Pradeep'},
          'requested_at': '2026-10-20T10:00:00Z',
        },
      };
      final f = DiscountBannerFacts.from(q, null)!;
      expect(f.title, 'Discount approval pending.');
      expect(f.body(date),
          ' 20% discount is above the 10% limit — requested by Neeraja Pradeep on 20 Oct 2026. It can’t be marked as sent until it’s approved.');
      expect(f.canDecide, isFalse);
      final latest = DiscountApproval.fromJson({'approval_id': 'a1', 'status': 'pending', 'can_decide': true});
      expect(DiscountBannerFacts.from(q, latest)!.canDecide, isTrue);
    });

    test('rejected banner with reviewer comment', () {
      final latest = DiscountApproval.fromJson({
        'approval_id': 'a1',
        'status': 'rejected',
        'limit_pct': '10.00',
        'review_comment': 'Keep it within 10%',
        'reviewed_by': {'full_name': 'Cijo G'},
        'can_decide': true,
      });
      final f = DiscountBannerFacts.from({'approval_status': 'REJECTED', 'discount_pct': '20.00'}, latest)!;
      expect(f.title, 'Discount approval rejected.');
      expect(f.body(date), ' The 20% discount was not approved by Cijo G — “Keep it within 10%”. Reduce the discount to send this quote.');
      expect(f.canDecide, isFalse);
    });

    test('no banner when approved / not required', () {
      expect(DiscountBannerFacts.from({'approval_status': 'APPROVED'}, null), isNull);
      expect(DiscountBannerFacts.from({'approval_status': 'NOT_REQUIRED'}, null), isNull);
    });
  });
}
