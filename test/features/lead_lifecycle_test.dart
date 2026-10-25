import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/crm/application/providers/lead_lifecycle_providers.dart';

void main() {
  group('LeadConversion.fromRow', () {
    test('Won alone is not converted', () {
      final c = LeadConversion.fromRow({'is_converted': false}, isWon: true);
      expect(c.isConverted, isFalse);
      expect(c.pendingApproval, isFalse);
    });

    test('a converted record links its customer', () {
      final c = LeadConversion.fromRow({
        'is_converted': true,
        'converted_customer': {'customer_id': 'c1', 'name': 'Elsa Mary'},
      }, isWon: true);
      expect(c.isConverted, isTrue);
      expect(c.customerId, 'c1');
      expect(c.customerName, 'Elsa Mary');
    });

    test('pending approval only counts when the org requires approval', () {
      final row = {'pending_conversion': {'approval_id': 'a1'}};
      expect(LeadConversion.fromRow(row, isWon: true).pendingApproval, isFalse);
      expect(
        LeadConversion.fromRow({...row, 'conversion_requires_approval': true}, isWon: true).pendingApproval,
        isTrue,
      );
    });

    test('quote mode waits for an accepted quote', () {
      final c = LeadConversion.fromRow(
          {'conversion_mode': 'quote', 'has_accepted_quote': false}, isWon: true);
      expect(c.waitingForQuote, isTrue);
    });

    test('lost reason text follows the webapp', () {
      expect(LeadConversion.fromRow({'lost_reason_name': 'Price', 'lost_reason_note': 'Too high'}, isWon: false)
          .lostReasonText, 'Price — Too high');
      expect(LeadConversion.fromRow({}, isWon: false).lostReasonText, 'No reason recorded');
    });
  });

  group('LostChoice body', () {
    test('sends the reason, a trimmed note and the credit flag only when set', () {
      expect(const LostChoice(reasonId: 'r1').toBody(), {'lost_reason': 'r1'});
      expect(const LostChoice(reasonId: 'r1', note: '  lost to X ', creditOpenInvoices: true).toBody(),
          {'lost_reason': 'r1', 'lost_reason_note': 'lost to X', 'credit_open_invoices': true});
    });
  });

  group('CustomerMatch', () {
    final match = CustomerMatch.fromError(const AppError(
      type: AppErrorType.conflict,
      message: 'A customer like this already exists.',
      statusCode: 409,
      code: 'CUSTOMER_MATCH',
      extra: {
        'cause': {
          'candidates': [
            {'customer_id': 'c1', 'reference': 'CU-1', 'name': 'Elsa Mary', 'match_on': ['name', 'email']},
          ],
          'hidden_count': 1,
          'suggested_name': 'Elsa Mary',
          'name_taken': true,
        },
      },
    ));

    test('parses candidates and labels the match', () {
      expect(match.candidates.single.id, 'c1');
      expect(match.candidates.single.matchLabel, 'Same name and email');
      expect(match.hiddenCount, 1);
    });

    test('name checks use the webapp copy', () {
      expect(match.nameProblem(' '), 'Enter a name for the new customer.');
      expect(match.nameProblem('Elsa Mary'),
          'A customer named “Elsa Mary” already exists. Enter a different name.');
      expect(match.nameProblem('Elsa Mary 2'), isNull);
    });
  });

  group('LostImpact', () {
    test('open invoices the user cannot credit block the move', () {
      final i = LostImpact.fromJson({
        'open_invoices': [
          {'number': 'INV-1', 'date': '2026-10-01', 'amount_due': '100.00'}
        ],
        'can_credit': false,
      });
      expect(i.hasOpenInvoices, isTrue);
      expect(i.blocked, isTrue);
    });

    test('only instalments not yet invoiced are counted', () {
      final i = LostImpact.fromJson({
        'open_instalments': [
          {'amount_expected': '50', 'invoiced': false},
          {'amount_expected': '70', 'invoiced': true},
        ],
      });
      expect(i.openInstalments, 1);
      expect(i.openInstalmentsAmount, 50);
    });
  });
}
