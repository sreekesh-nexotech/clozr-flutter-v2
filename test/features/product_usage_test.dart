// The product page's usage section. `GET /crm/products/{id}/usage/` reports the
// leads and quotes a catalog item appears on; nothing in the app read it, so the
// section was fed from `deals_count`/`usage_count` on the product record — keys
// the API never returns — and therefore stayed hidden even for an item on 11
// quotes.
//
// The rule that must hold both ways: show the section when there is activity,
// hide it when there is none, and never let it imply revenue figures the
// backend does not publish.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/domain/entities/product_usage.dart';

void main() {
  test('the documented shape maps to its counts', () {
    // Trimmed from a live response for NexoCRM Enterprise (Acme Corp).
    final usage = ProductUsage.fromJson(const {
      'leads_count': 6,
      'leads': [
        {'lead_id': 'l1', 'lead_name': 'Vikram Kapoor 1'},
      ],
      'quotes_count': 11,
      'quotes': [
        {'quotation_id': 'q1', 'quotation_number': 'QTN-00039'},
      ],
      'truncated': false,
    });

    expect(usage.quotes, 11);
    expect(usage.leads, 6);
    expect(usage.hasActivity, isTrue);
  });

  test('an unused item has no activity, so the section hides', () {
    final usage = ProductUsage.fromJson(const {
      'leads_count': 0,
      'leads': <dynamic>[],
      'quotes_count': 0,
      'quotes': <dynamic>[],
      'truncated': false,
    });
    expect(usage.hasActivity, isFalse);
  });

  test('activity on either axis alone is still activity', () {
    expect(
        ProductUsage.fromJson(const {'quotes_count': 1, 'leads_count': 0})
            .hasActivity,
        isTrue);
    expect(
        ProductUsage.fromJson(const {'quotes_count': 0, 'leads_count': 3})
            .hasActivity,
        isTrue);
  });

  test('a missing count falls back to the row count, not to zero', () {
    // Reporting "no activity" for an item whose rows are right there would
    // hide the section on exactly the product that needed it.
    final usage = ProductUsage.fromJson(const {
      'quotes': [
        {'quotation_id': 'q1'},
        {'quotation_id': 'q2'},
      ],
      'leads': [
        {'lead_id': 'l1'},
      ],
    });
    expect(usage.quotes, 2);
    expect(usage.leads, 1);
    expect(usage.hasActivity, isTrue);
  });

  test('a junk or empty body is no activity rather than a crash', () {
    for (final body in <Object?>[null, 'nope', 42, <dynamic>[], <String, dynamic>{}]) {
      final usage = ProductUsage.fromJson(body);
      expect(usage.hasActivity, isFalse, reason: '$body');
      expect(usage.quotes, 0);
      expect(usage.leads, 0);
    }
  });
}
