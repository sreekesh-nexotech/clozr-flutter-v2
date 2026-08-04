import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

void main() {
  const meUuid = '11111111-1111-4111-8111-111111111111';
  const otherUuid = '22222222-2222-4222-8222-222222222222';

  setUp(() {
    UserDirectory.currentUserId = meUuid;
  });

  tearDown(UserDirectory.reset);

  Map<String, dynamic> fullRow() {
    final now = DateTime.now();
    return {
      'lead_id': 'lead-uuid-1',
      'lead_name': 'Aboobacker Haji',
      'organization_name': 'Lulu Fashion Store',
      'status': 'Negotiation', // display NAME, not an id
      'status_id': 'status-uuid-1',
      'lead_value': 3650000,
      'lead_source': {'lead_source_id': 'src-1', 'name': 'Website'},
      'assignees': [
        {
          'user_id': meUuid,
          'first_name': 'Manoj',
          'last_name': 'Varma',
          'full_name': 'Manoj Varma',
          'email': 'manoj@example.in',
          'is_active': true,
        },
        {'user_id': otherUuid, 'full_name': 'Divya Rao'},
      ],
      'lead_owner': {'user_id': otherUuid, 'full_name': 'Divya Rao'},
      'activity': now.subtract(const Duration(hours: 5)).toIso8601String(),
      'last_followup_at':
          now.subtract(const Duration(days: 2)).toIso8601String(),
      'last_followup_type': 'call',
      'stage_entered_at':
          now.subtract(const Duration(days: 19)).toIso8601String(),
      'lead_score': 77,
      'custom_fields': {'budget': 5000000},
      'is_converted': false,
      'created_at': '2026-07-20T12:00:00Z',
      'phone': '+91 484 405 8890',
      'email': 'aboobacker@lulufashion.in',
      'website': 'www.lulufashion.in',
    };
  }

  group('LeadsRemoteDataSource.mapLead', () {
    test('maps a realistic list row onto the Lead entity', () {
      final lead = LeadsRemoteDataSource.mapLead(fullRow());

      expect(lead, isNotNull);
      expect(lead!.id, 'lead-uuid-1');
      expect(lead.name, 'Aboobacker Haji');
      expect(lead.initials, 'AH');
      expect(lead.company, 'Lulu Fashion Store');
      expect(lead.status, 'negotiation'); // display name → UI status key
      expect(lead.value, '₹36.5L'); // ₹ short-format
      expect(lead.valueNum, 3650000);
      expect(lead.score, 77);
      expect(lead.source, 'Website');
      expect(lead.project, 'Website'); // no products → lead_source name
      expect(lead.time, '5h ago');
      expect(lead.lastFu, 'Call · 2d ago');
      expect(lead.statusDays, 19);
      expect(lead.createdOn, contains('Jul 2026'));
      expect(lead.phone, '+91 484 405 8890');
      expect(lead.email, 'aboobacker@lulufashion.in');
      expect(lead.website, 'www.lulufashion.in');
      expect(lead.notif, 0);
      expect(lead.upsell, false);
      expect(lead.fromCustomerId, isNull);
    });

    test("maps the signed-in user's uuid to 'me' (owner + team)", () {
      final lead = LeadsRemoteDataSource.mapLead(fullRow())!;

      expect(lead.owner, otherUuid); // someone else stays a uuid
      expect(lead.team, contains('me')); // my uuid becomes the sentinel
      expect(lead.team, contains(otherUuid));
      expect(lead.isMine, isTrue);

      final mine = fullRow()..['lead_owner'] = {'user_id': meUuid, 'full_name': 'Manoj Varma'};
      expect(LeadsRemoteDataSource.mapLead(mine)!.owner, 'me');
    });

    test('prefers the first product name for project when products exist', () {
      final row = fullRow()
        ..['products'] = [
          {'product_id': 'p-1', 'product_name': 'Flagship fit-out', 'quantity': 1},
        ];
      expect(LeadsRemoteDataSource.mapLead(row)!.project, 'Flagship fit-out');
    });

    test('maps upsell + parent customer when present', () {
      final row = fullRow()
        ..['is_upsell'] = true
        ..['parent_customer'] = 'cust-uuid-9';
      final lead = LeadsRemoteDataSource.mapLead(row)!;
      expect(lead.upsell, isTrue);
      expect(lead.fromCustomerId, 'cust-uuid-9');
    });

    test('status falls back to status_type when the name is unknown', () {
      final row = fullRow()
        ..['status'] = 'Custom Stage'
        ..['status_type'] = 'won';
      expect(LeadsRemoteDataSource.mapLead(row)!.status, 'won');
    });

    test('tolerates a row missing every optional field', () {
      final lead = LeadsRemoteDataSource.mapLead({'lead_id': 'only-id'});

      expect(lead, isNotNull);
      expect(lead!.id, 'only-id');
      expect(lead.name, '');
      expect(lead.initials, '?');
      expect(lead.company, isNull);
      expect(lead.project, '');
      expect(lead.value, '₹0');
      expect(lead.valueNum, 0);
      expect(lead.status, 'new'); // safe default
      expect(lead.statusDays, 0);
      expect(lead.score, 0);
      expect(lead.source, '');
      expect(lead.owner, '');
      expect(lead.team, isEmpty);
      expect(lead.time, '');
      expect(lead.createdOn, '');
      expect(lead.lastFu, '');
      expect(lead.upsell, isFalse);
      expect(lead.fromCustomerId, isNull);
    });

    test('returns null for a row without lead_id', () {
      expect(LeadsRemoteDataSource.mapLead({'lead_name': 'No Id'}), isNull);
    });
  });

  group('LeadsRemoteDataSource.mapLeadRows', () {
    test('skips bad rows and keeps good ones', () {
      final rows = <dynamic>[
        fullRow(),
        {'lead_name': 'missing id'}, // no lead_id → skipped
        42, // not a map → skipped
        null, // skipped
        'garbage', // skipped
      ];
      final leads = LeadsRemoteDataSource.mapLeadRows(rows);
      expect(leads, hasLength(1));
      expect(leads.single.id, 'lead-uuid-1');
    });

    test('maps an empty list to an empty result', () {
      expect(LeadsRemoteDataSource.mapLeadRows(const []), isEmpty);
    });
  });
}
