import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/customers_remote_ds.dart';

void main() {
  const meUuid = '33333333-3333-4333-8333-333333333333';
  const otherUuid = '44444444-4444-4444-8444-444444444444';

  setUp(() {
    UserDirectory.currentUserId = meUuid;
  });

  tearDown(UserDirectory.reset);

  Map<String, dynamic> fullRow() {
    final now = DateTime.now();
    return {
      'customer_id': 'cust-uuid-1',
      'name': 'Ramesh Pillai',
      'status': 'status-uuid-1', // writable FK — NOT the display name
      'status_name': 'Upsell In Progress',
      'status_type': 'upsell_in_progress',
      'status_entered_at': '2025-12-08T12:00:00Z',
      'source': 'Referral',
      'value_need': {'value': '1800000.00', 'need': 'Showroom interiors'},
      'assignees': [
        {
          'user_id': meUuid,
          'full_name': 'Manoj Varma',
          'email': 'manoj@example.in',
          'first_name': 'Manoj',
          'last_name': 'Varma',
          'is_active': true,
        },
        {'user_id': otherUuid, 'full_name': 'Divya Rao'},
      ],
      'score': 70,
      'last_followup_at':
          now.subtract(const Duration(days: 2)).toIso8601String(),
      'last_followup_type': 'Call',
      'activity': now.subtract(const Duration(hours: 2)).toIso8601String(),
    };
  }

  group('CustomersRemoteDataSource.mapCustomer', () {
    test('maps a realistic list row onto the Customer entity', () {
      final customer = CustomersRemoteDataSource.mapCustomer(fullRow());

      expect(customer, isNotNull);
      expect(customer!.id, 'cust-uuid-1');
      expect(customer.name, 'Ramesh Pillai');
      expect(customer.initials, 'RP');
      expect(customer.company, ''); // organization_name absent on list rows
      expect(customer.status, 'upsell'); // status_type wins
      expect(customer.since, 'Dec 2025'); // from status_entered_at
      expect(customer.value, '₹18L'); // value_need.value, 2-dp string
      expect(customer.valueNum, 1800000);
      expect(customer.project, 'Showroom interiors'); // value_need.need
      expect(customer.score, 70);
      expect(customer.source, 'Referral');
      expect(customer.owner, ''); // no assigned_to on the list row
      expect(customer.team, contains('me'));
      expect(customer.team, contains(otherUuid));
      expect(customer.isMine, isTrue);
      expect(customer.isUpsell, isTrue);
      expect(customer.time, '2h ago');
      expect(customer.lastFu, 'Call · 2d ago');
      expect(customer.leadId, isNull);
      expect(customer.notif, 0);
    });

    test("maps assigned_to (object or bare uuid) to owner, with 'me' sentinel", () {
      final withObject = fullRow()
        ..['assigned_to'] = {'user_id': meUuid, 'full_name': 'Manoj Varma'};
      expect(CustomersRemoteDataSource.mapCustomer(withObject)!.owner, 'me');

      final withUuid = fullRow()..['assigned_to'] = otherUuid;
      expect(CustomersRemoteDataSource.mapCustomer(withUuid)!.owner, otherUuid);
    });

    test('falls back to revenue when value_need is absent', () {
      final row = fullRow()
        ..remove('value_need')
        ..['revenue'] = '2500000.00';
      final customer = CustomersRemoteDataSource.mapCustomer(row)!;
      expect(customer.value, '₹25L');
      expect(customer.valueNum, 2500000);
      expect(customer.project, ''); // no need text
    });

    test('maps detail-style contact fields when present', () {
      final row = fullRow()
        ..['organization_name'] = 'Kalyan Silks'
        ..['email'] = 'ramesh@kalyansilks.in'
        ..['phone'] = '+91 94100 11000'
        ..['industry_name'] = 'Retail'
        ..['address'] = 'Thrissur';
      final customer = CustomersRemoteDataSource.mapCustomer(row)!;
      expect(customer.company, 'Kalyan Silks');
      expect(customer.email, 'ramesh@kalyansilks.in');
      expect(customer.phone, '+91 94100 11000');
      expect(customer.industry, 'Retail');
      expect(customer.location, 'Thrissur');
    });

    test('status falls back to name matching, then active', () {
      final named = fullRow()
        ..remove('status_type')
        ..['status_name'] = 'Project Completed';
      expect(CustomersRemoteDataSource.mapCustomer(named)!.status, 'completed');

      final unknown = fullRow()
        ..remove('status_type')
        ..['status_name'] = 'Something Custom';
      expect(CustomersRemoteDataSource.mapCustomer(unknown)!.status, 'active');
    });

    test('tolerates a row missing every optional field', () {
      final customer =
          CustomersRemoteDataSource.mapCustomer({'customer_id': 'only-id'});

      expect(customer, isNotNull);
      expect(customer!.id, 'only-id');
      expect(customer.name, '');
      expect(customer.initials, '?');
      expect(customer.company, '');
      expect(customer.status, 'active'); // safe default
      expect(customer.since, '');
      expect(customer.statusDays, 0);
      expect(customer.value, '₹0');
      expect(customer.valueNum, 0);
      expect(customer.project, '');
      expect(customer.score, 0);
      expect(customer.owner, '');
      expect(customer.team, isEmpty);
      expect(customer.time, '');
      expect(customer.lastFu, '');
      expect(customer.createdOn, '');
      expect(customer.leadId, isNull);
    });

    test('returns null for a row without customer_id', () {
      expect(CustomersRemoteDataSource.mapCustomer({'name': 'No Id'}), isNull);
    });
  });

  group('CustomersRemoteDataSource.mapCustomerRows', () {
    test('skips bad rows and keeps good ones', () {
      final rows = <dynamic>[
        {'name': 'missing id'}, // no customer_id → skipped
        fullRow(),
        3.14, // not a map → skipped
        null, // skipped
      ];
      final customers = CustomersRemoteDataSource.mapCustomerRows(rows);
      expect(customers, hasLength(1));
      expect(customers.single.id, 'cust-uuid-1');
    });

    test('maps an empty list to an empty result', () {
      expect(CustomersRemoteDataSource.mapCustomerRows(const []), isEmpty);
    });
  });
}
