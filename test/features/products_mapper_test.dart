import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/products_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('productFromApi', () {
    test('maps a full row: money strings, gst/gross computed, category kept', () {
      final p = productFromApi({
        'product_id': 'uuid-1',
        'product_name': 'Turnkey Office Fit-out',
        'product_type': {'name': 'Fit-out'},
        'hsn_code': '995461',
        'unit': 'per sq.ft.',
        'price': '2400.00',
        'is_active': true,
        'description': 'End-to-end fit-out.',
      })!;

      expect(p.id, 'uuid-1');
      expect(p.name, 'Turnkey Office Fit-out');
      expect(p.kind, 'product');
      expect(p.cat, 'Fit-out');
      expect(p.hsn, '995461');
      expect(p.unit, 'per sq.ft.');
      expect(p.price, '₹2.4K');
      expect(p.gst, 18);
      expect(p.gstAmt, '₹432');
      expect(p.gross, '₹2.8K');
      expect(p.active, isTrue);
      expect(p.desc, 'End-to-end fit-out.');
    });

    test('defensive defaults on a minimal row', () {
      final p = productFromApi({'product_id': 'uuid-min'})!;

      expect(p.name, '');
      expect(p.kind, 'product');
      expect(p.cat, '');
      expect(p.hsn, '');
      expect(p.unit, '');
      expect(p.price, '₹0');
      expect(p.gst, 18);
      expect(p.deals, 0);
      expect(p.revenue, '₹0');
      expect(p.revNum, 0);
      expect(p.avg, '—');
      expect(p.active, isTrue);
      expect(p.desc, isNull);
      expect(p.notes, isEmpty);
    });

    test('package detection from type/category naming; inactive respected', () {
      final byType = productFromApi({
        'product_id': 'uuid-pkg',
        'product_name': 'Office Starter',
        'product_type': {'name': 'Interior Package'},
        'is_active': false,
      })!;
      expect(byType.kind, 'package');
      expect(byType.cat, 'Interior Package');
      expect(byType.active, isFalse);

      final byCategory = productFromApi({
        'product_id': 'uuid-pkg2',
        'product_name': 'Retail Refresh',
        'category': 'package',
      })!;
      expect(byCategory.kind, 'package');
    });

    test('field-name variants: category string, tax_percent, usage fields', () {
      final p = productFromApi({
        'product_id': 'uuid-v',
        'product_name': 'Custom Widget',
        'category': 'Custom Widgets',
        'tax_percent': 12,
        'price': 100000,
        'deals': 4,
        'revenue': '800000.00',
      })!;

      // Unknown category kept raw — the list handles unknown keys gracefully.
      expect(p.cat, 'Custom Widgets');
      expect(p.gst, 12);
      expect(p.price, '₹1L');
      expect(p.gstAmt, '₹12K');
      expect(p.gross, '₹1.1L');
      expect(p.deals, 4);
      expect(p.revenue, '₹8L');
      expect(p.revNum, 800000);
      expect(p.avg, '₹2L');
    });

    test('rows without product_id are skipped, never fatal', () {
      expect(productFromApi({'product_name': 'No id'}), isNull);
      final list = productsFromApiRows([
        {'product_name': 'No id'},
        {'product_id': 'uuid-ok', 'product_name': 'Kept'},
        'junk',
        null,
      ]);
      expect(list, hasLength(1));
      expect(list.single.id, 'uuid-ok');
    });
  });
}
