// Product `short_name` (Oct 2026): lists show it when set, else the full
// product name; detail screens keep the full name. A blank short name clears
// it, and more than 60 characters is refused.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/product_display.dart';

void main() {
  group('a product in a list', () {
    test('reads by its short name when one is set', () {
      expect(
          productListName({
            'product_name': 'Solar Panel 540W Bifacial',
            'short_name': 'Panel 540W'
          }),
          'Panel 540W');
    });

    test('falls back to the full name when the short name is blank', () {
      expect(
          productListName(
              {'product_name': 'Solar Panel 540W Bifacial', 'short_name': ''}),
          'Solar Panel 540W Bifacial');
      expect(
          productListName({
            'product_name': 'Solar Panel 540W Bifacial',
            'short_name': '   '
          }),
          'Solar Panel 540W Bifacial');
      // A payload from before the field existed.
      expect(productListName({'product_name': 'Solar Panel 540W Bifacial'}),
          'Solar Panel 540W Bifacial');
    });

    test('names nothing when the item carries no name at all', () {
      expect(productListName({'product_id': 'x'}), '');
    });
  });

  group('editing the short name', () {
    test('a blank box clears it; text is trimmed', () {
      expect(productShortNameWriteValue('  '), isNull);
      expect(productShortNameWriteValue(' Panel 540W '), 'Panel 540W');
    });

    test('more than 60 characters is refused before the round trip', () {
      expect(productShortNameError('a' * 60), isNull);
      expect(productShortNameError('a' * 61), isNotNull);
      expect(productShortNameError(''), isNull);
    });
  });
}
