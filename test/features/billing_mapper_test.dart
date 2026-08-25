// The Billing screen was static: "14 GB / 50 GB" storage, three invented
// invoice numbers all reading "Paid · ₹56,640", and a Change-plan button that
// only toasted. There is no `billing.md`, so these fixtures are rows taken off
// the live endpoints.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/billing_remote_ds.dart';

void main() {
  group('invoice', () {
    Map<String, dynamic> row() => {
          'invoice_id': '4cb7ae59-9c7e-431f-b062-37ad8aebf866',
          'invoice_number': 'INV-2026-08-3fac318f-008',
          'period_start': '2026-08-12T18:01:02.873202Z',
          'period_end': '2026-08-26T06:09:49.863443Z',
          'subtotal': '1999.00',
          'tax_amount': '0.00',
          'total_amount': '1999.00',
          'amount_paid': '1999.00',
          'amount_due': '0.00',
          'status': 'paid',
          'due_date': '2026-08-12T18:01:02.873202Z',
          'paid_at': '2026-08-12T18:01:13.791331Z',
          'line_items': [
            {
              'description': '1 license(s) added mid-cycle — prorated to cycle end',
              'item_type': 'prorated',
              'quantity': 1,
              'unit_price': '1999.00',
              'is_prorated': true,
              'subtotal': '1999.00',
            },
          ],
        };

    test('maps the number, money and period', () {
      final inv = BillingRemoteDataSource.invoiceFromJson(row());
      expect(inv.number, 'INV-2026-08-3fac318f-008');
      expect(inv.total, 1999.00);
      expect(inv.periodStart, isNotNull);
      expect(inv.periodEnd, isNotNull);
    });

    test('paid means paid, and nothing outstanding', () {
      final inv = BillingRemoteDataSource.invoiceFromJson(row());
      expect(inv.isPaid, isTrue);
      expect(inv.isOutstanding, isFalse);
    });

    test('money still due is outstanding whatever the status word says', () {
      final inv = BillingRemoteDataSource.invoiceFromJson(
          {...row(), 'status': 'paid', 'amount_due': '500.00'});
      expect(inv.isOutstanding, isTrue);
    });

    test('an unknown status word passes through rather than being folded', () {
      final inv =
          BillingRemoteDataSource.invoiceFromJson({...row(), 'status': 'void'});
      expect(inv.status, 'void');
      expect(inv.isPaid, isFalse);
    });

    test('line items carry their prorated flag', () {
      final item = BillingRemoteDataSource.invoiceFromJson(row()).lineItems.single;
      expect(item.isProrated, isTrue);
      expect(item.quantity, 1);
      expect(item.subtotal, 1999.00);
    });
  });

  group('storage', () {
    test('an unlimited plan has no fraction to draw', () {
      // Exactly what the dev org returns.
      final s = BillingRemoteDataSource.storageFromJson({
        'used_bytes': 9307669,
        'used_display': '8.88 MB',
        'limit_display': null,
        'limit_bytes': null,
        'percent': null,
        'unlimited': true,
      });
      expect(s.unlimited, isTrue);
      expect(s.headline, '8.88 MB');
      expect(s.fraction, 0, reason: 'a full bar would read as a quota running out');
    });

    test('a capped plan reads as used-of-limit', () {
      final s = BillingRemoteDataSource.storageFromJson({
        'used_display': '14 GB',
        'limit_display': '50 GB',
        'limit_bytes': 53687091200,
        'percent': 28.0,
        'unlimited': false,
      });
      expect(s.headline, '14 GB of 50 GB');
      expect(s.fraction, closeTo(0.28, 0.001));
    });

    test('a null cap means unlimited even without the flag', () {
      final s = BillingRemoteDataSource.storageFromJson(
          {'used_display': '1 MB', 'limit_bytes': null});
      expect(s.unlimited, isTrue);
    });

    test('a shape that loses everything degrades rather than throwing', () {
      expect(BillingRemoteDataSource.storageFromJson(null).headline, '—');
    });
  });

  group('plan', () {
    Map<String, dynamic> row() => {
          'plan_id': 'f22a4d61-c20b-400b-8f4a-1dfb4196f83c',
          'name': 'Professional',
          'description': 'Growing teams…',
          'monthly_price_per_user': '999.00',
          'annual_price_per_user': '9999.00',
          'features': {
            'helpdesk': true,
            'projects': true,
            'whatsapp': false,
            'limits.users': 25,
          },
        };

    test('maps both prices', () {
      final p = BillingRemoteDataSource.planFromJson(row());
      expect(p.monthlyPerUser, 999.00);
      expect(p.annualPerUser, 9999.00);
    });

    test('only the switched-on modules count as enabled', () {
      final p = BillingRemoteDataSource.planFromJson(row());
      expect(p.enabledModules, containsAll(['helpdesk', 'projects']));
      expect(p.enabledModules, isNot(contains('whatsapp')));
      expect(p.enabledModules, isNot(contains('limits.users')));
    });

    test('a numeric cap reads as a limit, a null one as unlimited', () {
      expect(BillingRemoteDataSource.planFromJson(row()).userLimitLabel,
          'Up to 25 users');
      final open = BillingRemoteDataSource.planFromJson({
        ...row(),
        'features': {'limits.users': null},
      });
      expect(open.userLimitLabel, 'Unlimited users');
    });

    test('a plan with no limits key claims none', () {
      final p = BillingRemoteDataSource.planFromJson(
          {...row(), 'features': <String, dynamic>{}});
      expect(p.userLimitLabel, isNull);
    });
  });
}
