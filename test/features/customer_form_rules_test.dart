import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/customer_form_rules.dart';
import 'package:clozrapp/features/crm/domain/repositories/customers_repository.dart';
import 'package:clozrapp/features/crm/presentation/components/duplicate_notice.dart';

void main() {
  group('GSTIN', () {
    test('trimmed, spaces removed and upper-cased', () {
      expect(normalizeGstin(' 32abcde1234f1z5 '), '32ABCDE1234F1Z5');
      expect(normalizeGstin('32 abcde 1234f1z5'), '32ABCDE1234F1Z5');
    });
    test('blank is null', () {
      expect(normalizeGstin('   '), isNull);
    });
    test('hint copy', () {
      expect(gstinHint, "15 characters; its first two digits are the billing state's GST code.");
    });
  });

  group('create payload', () {
    final billing = {
      'billing_address_line1': ' 12 MG Road ',
      'billing_address_line2': '',
      'billing_city': 'Kochi',
      'billing_state_code': '32',
      'billing_pincode': '682001',
      'gstin': ' 32abcde1234f1z5 ',
    };

    test('same as billing copies billing into delivery and drops blanks', () {
      final p = customerAddressPayload({
        ...billing,
        'delivery_city': 'Ignored',
      }, sameAsBilling: true);
      expect(p, {
        'billing_address_line1': '12 MG Road',
        'billing_city': 'Kochi',
        'billing_state_code': '32',
        'billing_pincode': '682001',
        'delivery_address_line1': '12 MG Road',
        'delivery_city': 'Kochi',
        'delivery_state_code': '32',
        'delivery_pincode': '682001',
        'gstin': '32ABCDE1234F1Z5',
      });
    });

    test('unticked sends the delivery inputs as typed', () {
      final p = customerAddressPayload({
        ...billing,
        'delivery_city': 'Thrissur',
        'delivery_state_code': '32',
      }, sameAsBilling: false);
      expect(p['delivery_city'], 'Thrissur');
      expect(p['delivery_state_code'], '32');
      expect(p.containsKey('delivery_address_line1'), isFalse);
    });

    test('an empty block sends nothing', () {
      expect(customerAddressPayload(const {}, sameAsBilling: true), isEmpty);
    });
  });

  group('edit patch', () {
    test('untouched block against a record without the columns is empty', () {
      final row = <String, dynamic>{'name': 'X', 'gstin': null, 'address': ''};
      final values = addressValuesFromRow(row);
      expect(customerAddressPatch(values, row, sameAsBilling: deliveryMatchesBilling(row)), isEmpty);
    });

    test('changed and cleared values only; cleared goes as null', () {
      final row = <String, dynamic>{'billing_city': 'Kochi', 'gstin': '32ABCDE1234F1Z5'};
      final values = {...addressValuesFromRow(row), 'billing_city': '', 'billing_pincode': '682001'};
      final patch = customerAddressPatch(values, row, sameAsBilling: false);
      expect(patch, {'billing_city': null, 'billing_pincode': '682001'});
    });

    test('same-as-billing seeds from the record', () {
      expect(deliveryMatchesBilling(null), isTrue);
      expect(deliveryMatchesBilling({'billing_city': 'Kochi', 'delivery_city': 'Kochi'}), isTrue);
      expect(deliveryMatchesBilling({'billing_city': 'Kochi', 'delivery_city': 'Thrissur'}), isFalse);
    });
  });

  group('error routing', () {
    test('address keys land on their input; delivery folds onto billing when same', () {
      expect(addressErrorField('gstin', sameAsBilling: true), 'gstin');
      expect(addressErrorField('billing_pincode', sameAsBilling: false), 'billing_pincode');
      expect(addressErrorField('delivery_pincode', sameAsBilling: true), 'billing_pincode');
      expect(addressErrorField('delivery_pincode', sameAsBilling: false), 'delivery_pincode');
      expect(addressErrorField('address', sameAsBilling: true), 'billing_address_line1');
      expect(addressErrorField('email', sameAsBilling: true), isNull);
    });

    test('first message per field', () {
      expect(
        firstFieldErrors({
          'name': ['A customer with this name already exists.'],
          'email': ['Enter a valid email address.', 'x'],
          'phone': [],
        }),
        {'name': 'A customer with this name already exists.', 'email': 'Enter a valid email address.'},
      );
    });

    test('schema columns owned by the block', () {
      expect(isAddressFormField('address'), isTrue);
      expect(isAddressFormField('delivery_country'), isTrue);
      expect(isAddressFormField('gstin'), isTrue);
      expect(isAddressFormField('email'), isFalse);
    });
  });

  test('default status is the Active-type one', () {
    const statuses = [
      CustomerStatus(id: '10', name: 'Completed', statusType: 'completed'),
      CustomerStatus(id: '9', name: 'Active', statusType: 'active'),
    ];
    expect(defaultCustomerStatusId(statuses), '9');
    expect(defaultCustomerStatusId(const []), isNull);
  });

  group('duplicate parsing (customer create)', () {
    test('block: 400 errors.duplicate', () {
      final d = LeadDuplicate.parse({
        'type': 'duplicate',
        'match_keys': ['email', 'phone'],
        'matched': {
          'customers': [
            {'customer_id': 'c1', 'name': 'Manoj Nair', 'email': 'manoj.nair@example.com'},
          ],
          'leads': [
            {'lead_id': 'l1', 'lead_name': 'Manoj', 'email': 'None'},
          ],
        },
      })!;
      expect(d.keysText, 'email or phone');
      expect(d.customers.single.id, 'c1');
      expect(d.customers.single.name, 'Manoj Nair');
      expect(d.leads.single.id, 'l1');
      expect(d.leads.single.email, '');
    });

    test('warn: 201 warnings entry', () {
      final d = LeadDuplicate.fromWarnings([
        {
          'match_keys': ['email'],
          'matched': {
            'customers': [
              {'customer_id': 'c1', 'name': 'Manoj Nair'},
            ],
          },
        },
      ]);
      expect(d, isNotNull);
      expect(d!.keysText, 'email');
      expect(LeadDuplicate.fromWarnings(null), isNull);
      expect(LeadDuplicate.fromWarnings(const []), isNull);
    });
  });
}
