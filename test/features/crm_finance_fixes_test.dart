import 'package:clozrapp/features/crm/application/providers/crm_party_providers.dart';
import 'package:clozrapp/features/crm/application/providers/invoices_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/customer.dart';
import 'package:clozrapp/features/crm/domain/entities/invoice.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/invoices_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal [Customer] for lookup tests — only id / name / company matter here.
Customer _customer({required String id, required String name, String? company}) => Customer(
      id: id,
      leadId: null,
      name: name,
      initials: '',
      company: company,
      project: '',
      value: '',
      valueNum: 0,
      status: 'active',
      since: '',
      statusDays: 0,
      score: 0,
      source: '',
      owner: 'me',
      team: const [],
      phone: '',
      email: '',
      website: '',
      industry: '',
      location: '',
      createdOn: '',
      time: '',
      lastFu: '',
      notif: 0,
    );

Invoice _invoice({String? custId}) => Invoice(
      id: 'INV-1',
      custId: custId,
      quoteId: null,
      type: 'Installments',
      total: '₹10L',
      totalNum: 1000000,
      settled: 0,
      of: 0,
      balance: '₹10L',
      status: 'unpaid',
    );

void main() {
  group('invoiceFromApi — cancelled records excluded from settled/of (M2)', () {
    test('cancelled records do not inflate "settled X of Y"', () {
      final iv = invoiceFromApi({
        'payment_id': 'uuid-p',
        'quotation_number': 'QUO-9',
        'payment_type': 'installment_custom',
        'total_amount': '1000000.00',
        'amount_paid': '400000.00',
        'amount_remaining': '600000.00',
        'status': 'active',
        'records': [
          {'status': 'paid'},
          {'status': 'pending'},
          {'status': 'cancelled'},
          {'status': 'cancelled'},
        ],
      })!;

      // 4 records, 2 cancelled → schedule is the 2 live ones; 1 of them paid.
      expect(iv.of, 2);
      expect(iv.settled, 1);
      expect(iv.progress, closeTo(0.5, 0.001));
    });

    test('a schedule of only cancelled records collapses to 0 of 0', () {
      final iv = invoiceFromApi({
        'payment_id': 'uuid-p2',
        'payment_type': 'installment_even',
        'total_amount': '500000.00',
        'amount_paid': '0.00',
        'status': 'active',
        'records': [
          {'status': 'cancelled'},
          {'status': 'CANCELLED'}, // case-insensitive
        ],
      })!;

      expect(iv.of, 0);
      expect(iv.settled, 0);
      expect(iv.progress, 0);
    });
  });

  group('customerPartyLookup — API-mode resolution (CrmPartyDirectory leak)', () {
    final customers = [
      _customer(id: 'CUST-1', name: 'Asha Rao', company: 'Bluewave Interiors'),
      _customer(id: 'CUST-2', name: 'Vinod K', company: null),
    ];
    final lookup = customerPartyLookup(customers);

    test('a known customer id resolves to its real name/company', () {
      final p = lookup(custId: 'CUST-1');
      expect(p, isNotNull);
      expect(p!.name, 'Asha Rao');
      expect(p.company, 'Bluewave Interiors');
    });

    test('a null company becomes an empty string, name preserved', () {
      final p = lookup(custId: 'CUST-2')!;
      expect(p.company, '');
      expect(p.name, 'Vinod K');
    });

    test('an unknown id resolves to null — never a fabricated seed name', () {
      // 'C2001' is a CrmPartyDirectory seed id (Ramesh Pillai / Kalyan Silks).
      // API mode must NOT leak that fake identity.
      expect(lookup(custId: 'C2001'), isNull);
      expect(lookup(custId: 'nope'), isNull);
      expect(lookup(custId: null), isNull);
    });

    test('a lead-only reference resolves to null in API mode', () {
      expect(lookup(leadId: 'L1010'), isNull);
    });

    test('invoiceWho falls back to the raw custId when the party is unknown', () {
      expect(invoiceWho(_invoice(custId: 'CUST-9'), lookup), 'CUST-9');
      expect(invoiceWho(_invoice(custId: null), lookup), '—');
      expect(invoiceWho(_invoice(custId: 'CUST-1'), lookup), 'Bluewave Interiors');
    });
  });
}
