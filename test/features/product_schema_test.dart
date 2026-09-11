// The Products detail readout and the Add-product form are rendered from the
// org's own layout (`GET /crm/products/schema/?view_type=detail`, which
// `products.md` §1 says backs the modal too) rather than a fixed field list.
//
// Two things have to hold: the panel shows what the org configured — including
// its custom product fields — without printing identifiers or the documented
// stubs, and the form never renders a field whose value the API would discard.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/product_columns.dart';
import 'package:clozrapp/features/crm/application/product_form.dart';
import 'package:clozrapp/features/crm/application/record_rows.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';

/// A detail-view schema in the documented shape (§1): mandatory columns first,
/// an org-added one, a custom field, and the stubs an org may well leave
/// visible because they are real serializer fields.
final _schemaBody = <String, dynamic>{
  'model': 'Product',
  'view_type': 'detail',
  'has_org_config': true,
  'fields': {
    'product_code': {'name': 'product_code', 'type': 'string'},
    'billing_unit': {'name': 'billing_unit', 'type': 'string'},
    'tax_rate': {'name': 'tax_rate', 'type': 'decimal'},
    'item_type': {
      'name': 'item_type',
      'type': 'string',
      'choices': [
        {'value': 'product', 'label': 'Product'},
        {'value': 'package', 'label': 'Package'},
      ],
    },
    'product_type': {
      'name': 'product_type',
      'type': 'foreignkey',
      'related_model': 'ProductType',
    },
    'custom_fields.warranty': {
      'name': 'custom_fields.warranty',
      'label': 'Warranty',
      'type': 'string',
      'is_custom': true,
    },
  },
  'all_fields': {
    'columns': [
      {'name': 'product_id', 'label': 'ID', 'order': 1, 'visible': true, 'is_fixed': true},
      {
        'name': 'product_name',
        'label': 'Product',
        'order': 2,
        'visible': true,
        'is_fixed': true,
        'field_info': {'type': 'string'},
      },
      {
        'name': 'product_type_name',
        'label': 'Category',
        'order': 3,
        'visible': true,
        'is_fixed': true,
      },
      {
        'name': 'product_type',
        'label': 'Category id',
        'order': 4,
        'visible': true,
        'field_info': {'type': 'foreignkey', 'related_model': 'ProductType'},
      },
      {
        'name': 'product_code',
        'label': 'SKU',
        'order': 5,
        'visible': true,
        'field_info': {'type': 'string'},
      },
      {
        'name': 'billing_unit',
        'label': 'Billed by',
        'order': 6,
        'visible': true,
        'field_info': {'type': 'string'},
      },
      {
        'name': 'tax_rate',
        'label': 'GST',
        'order': 7,
        'visible': true,
        'field_info': {'type': 'decimal'},
      },
      {
        'name': 'item_type',
        'label': 'Item type',
        'order': 8,
        'visible': true,
        'field_info': {'type': 'string'},
      },
      {
        'name': 'price',
        'label': 'Price',
        'order': 9,
        'visible': true,
        'field_info': {'type': 'decimal'},
      },
      {
        'name': 'is_active',
        'label': 'Active',
        'order': 10,
        'visible': true,
        'field_info': {'type': 'boolean'},
      },
      {
        'name': 'custom_fields.warranty',
        'label': 'Warranty',
        'order': 11,
        'visible': true,
        'field_info': {'type': 'string', 'is_custom': true},
      },
      {'name': 'deals_count', 'label': 'Deals using this', 'order': 12, 'visible': true},
      {'name': 'hsn_sac', 'label': 'HSN / SAC', 'order': 13, 'visible': false},
    ],
  },
};

/// `GET /crm/products/{id}/` — `fields = "__all__"`, so the row carries more
/// than the layout mentions (§2).
const _row = <String, dynamic>{
  'product_id': '7f0c-uuid',
  'product_name': 'Reception joinery',
  'product_type': 'a1b2-uuid',
  'product_type_name': 'Joinery',
  'product_code': 'JN-RECEP',
  'billing_unit': 'per package',
  'tax_rate': '18.00',
  'item_type': 'product',
  'price': '320000.000000',
  'currency': 'INR',
  'is_active': true,
  'hsn_sac': '940360',
  'deals_count': 0,
  'lifetime_revenue': null,
  'custom_fields': {'warranty': '2 years'},
};

void main() {
  final schema = ViewSchema.fromResponse(_schemaBody);

  group('detail panel', () {
    final rows = recordRows(_row, schema, skip: kProductDetailChromeColumns);
    Map<String, String> byLabel() => {for (final r in rows) r.label: r.value};

    test('renders the org label and order, not a built-in list', () {
      // "GST" is absent because the pricing card above already states the rate
      // — the same reason Price and Active are absent.
      expect([for (final r in rows) r.label],
          ['Category', 'SKU', 'Billed by', 'Item type', 'Warranty']);
    });

    test('a custom product field reaches the panel', () {
      // The whole point of §1's `product` custom-field set: it lives under
      // `custom_fields.warranty` and no hardcoded row could ever show it.
      expect(byLabel()['Warranty'], '2 years');
    });

    test('the category shows its name, never its uuid', () {
      // `product_type_name` is mandatory (§1), so skipping the uuid column
      // never loses the category.
      expect(byLabel()['Category'], 'Joinery');
      expect(rows.any((r) => r.value.contains('a1b2-uuid')), isFalse);
    });

    test('chrome the page already draws is not repeated', () {
      for (final label in const ['Product', 'Price', 'Active']) {
        expect(byLabel().containsKey(label), isFalse, reason: label);
      }
    });

    test('the documented stubs stay out', () {
      // `deals_count` is `0` until the quote↔product link lands (§2, gap 4);
      // a row reading "0" states it as fact.
      expect(byLabel().containsKey('Deals using this'), isFalse);
    });

    test('a hidden column stays hidden', () {
      expect(byLabel().containsKey('HSN / SAC'), isFalse);
    });

    test('a visible column the record has no value for renders as a dash', () {
      final sparse = recordRows(
        const {'product_type_name': 'Joinery', 'custom_fields': <String, dynamic>{}},
        schema,
        skip: kProductDetailChromeColumns,
      );
      expect(sparse.firstWhere((r) => r.name == 'product_code').value, '—');
    });
  });

  group('form schema', () {
    test('a product form drops only the fields the modal owns', () {
      final form = productFormSchema(schema, isPackage: false);
      final names = [for (final c in form.editableColumns) c.name];
      // `product_name` is the modal's explicit first input; `item_type` is the
      // toggle's, and immutable after create (§4).
      expect(names, isNot(contains('product_name')));
      expect(names, isNot(contains('item_type')));
      // Everything else the org configured stays, price and status included.
      expect(names, containsAll(['product_type', 'product_code', 'billing_unit', 'tax_rate', 'price', 'is_active']));
    });

    test('a package form also drops the derived price and the status', () {
      final form = productFormSchema(schema, isPackage: true);
      final names = [for (final c in form.editableColumns) c.name];
      // §7: the price is recomputed from the components, and an active package
      // with no components is a 400 — this sheet has no component editor.
      expect(names, isNot(contains('price')));
      expect(names, isNot(contains('is_active')));
      expect(names, contains('product_code'));
    });

    test('display-only columns are never rendered as inputs', () {
      // `product_id` and `product_type_name` arrive with no `field_info`, so
      // they are readouts — a box around either accepts input the API discards.
      final names = [
        for (final c in productFormSchema(schema, isPackage: false).editableColumns) c.name,
      ];
      expect(names, isNot(contains('product_id')));
      expect(names, isNot(contains('product_type_name')));
    });

    test('an empty schema stays empty, which is the built-in form signal', () {
      expect(productFormSchema(ViewSchema.empty, isPackage: false).editableColumns, isEmpty);
    });
  });

  group('create payload', () {
    test('carries the schema fields plus the two keys the modal owns', () {
      final payload = productCreatePayload(
        const {
          'product_code': 'JN-RECEP',
          'product_type': 'a1b2-uuid',
          'billing_unit': 'per package',
          'tax_rate': 18,
          'price': 320000,
          'is_active': true,
        },
        name: '  Reception joinery  ',
        isPackage: false,
      );
      expect(payload['product_name'], 'Reception joinery');
      expect(payload['item_type'], 'product');
      expect(payload['product_type'], 'a1b2-uuid');
      expect(payload['tax_rate'], 18);
      expect(payload['price'], 320000);
      expect(payload['is_active'], true);
    });

    test('empty boxes are omitted, not posted as ""', () {
      // `product_code` is unique per org (§3) — posting `""` stores the empty
      // code, and the next blank create collides with it.
      final payload = productCreatePayload(
        const {'product_code': '', 'hsn_sac': '   ', 'description': 'Real text'},
        name: 'Reception joinery',
        isPackage: false,
      );
      expect(payload.containsKey('product_code'), isFalse);
      expect(payload.containsKey('hsn_sac'), isFalse);
      expect(payload['description'], 'Real text');
    });

    test('false and zero survive the empty-value sweep', () {
      final payload = productCreatePayload(
        const {'is_active': false, 'tax_rate': 0},
        name: 'Zero-rated service',
        isPackage: false,
      );
      expect(payload['is_active'], false);
      expect(payload['tax_rate'], 0);
    });

    test('a package never sends a price, and is created inactive', () {
      final payload = productCreatePayload(
        const {'price': 500000, 'is_active': true, 'components': [], 'product_code': 'PKG-1'},
        name: 'Starter bundle',
        isPackage: true,
      );
      expect(payload.containsKey('price'), isFalse);
      expect(payload['is_active'], false);
      expect(payload.containsKey('components'), isFalse);
      expect(payload['item_type'], 'package');
      expect(payload['product_code'], 'PKG-1');
    });
  });
}
