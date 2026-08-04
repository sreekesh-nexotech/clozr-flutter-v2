import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/invoices_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/payments_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/quotes_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(UserDirectory.reset);

  group('quoteFromApi', () {
    test('maps a full row: decimal-string money, dates, items, linkage', () {
      final q = quoteFromApi({
        'quotation_id': 'uuid-q',
        'quotation_number': 'QUO-2041',
        'customer_id': 'uuid-c',
        'status': {'name': 'Sent'},
        'total_amount': '3650000.00',
        'valid_until': '2126-07-15',
        'created_at': '2026-06-15',
        'payment_type': 'installment_custom',
        'currency': 'INR',
        'is_converted': false,
        'owner': 'uuid-other',
        'items': [
          {
            'product_name': 'Boutique wing fit-out',
            'quantity': 2,
            'unit_price': '900000.00',
            'amount': '1800000.00',
          },
          {'name': 'Lighting package', 'qty': 3, 'rate': 200000},
        ],
        'notes': 'Approved over call.',
      })!;

      expect(q.id, 'QUO-2041');
      expect(q.custId, 'uuid-c');
      expect(q.leadId, isNull);
      expect(q.status, 'sent');
      expect(q.amount, '₹36.5L');
      expect(q.amountNum, 3650000);
      expect(q.issued, '15 Jun 2026');
      expect(q.valid, '15 Jul 2126');
      expect(q.payType, 'Installments');
      expect(q.currency, 'INR');
      expect(q.owner, 'uuid-other');
      expect(q.items, hasLength(2));
      expect(q.items.first.name, 'Boutique wing fit-out');
      expect(q.items.first.qty, 2);
      expect(q.items.first.rate, '₹9L');
      expect(q.items.first.amt, '₹18L');
      // No explicit amount on the second item → qty × rate.
      expect(q.items[1].rate, '₹2L');
      expect(q.items[1].amt, '₹6L');
      expect(q.note, 'Approved over call.');
    });

    test('a sent quote past its validity maps to effective expired', () {
      final q = quoteFromApi({
        'quotation_number': 'QUO-1',
        'status': 'Sent',
        'valid_until': '2020-01-15',
      })!;
      expect(q.status, 'expired');
    });

    test('is_converted wins over the status name', () {
      final q = quoteFromApi({
        'quotation_number': 'QUO-2',
        'status': 'Sent',
        'is_converted': true,
        'valid_until': '2020-01-15',
      })!;
      expect(q.status, 'accepted');
    });

    test('signed-in owner uuid maps to me', () {
      UserDirectory.currentUserId = 'uuid-me';
      final q = quoteFromApi({
        'quotation_number': 'QUO-3',
        'owner': {'user_id': 'uuid-me', 'full_name': 'Me User'},
      })!;
      expect(q.owner, 'me');
    });

    test('defensive defaults + id fallback; no id at all is skipped', () {
      final q = quoteFromApi({'quotation_id': 'uuid-only'})!;
      expect(q.id, 'uuid-only');
      expect(q.status, 'draft');
      expect(q.template, 'Standard');
      expect(q.payType, 'Lump sum');
      expect(q.currency, 'INR');
      expect(q.amount, '₹0');
      expect(q.items, isEmpty);
      expect(q.dueDate, '');
      expect(q.note, isNull);

      expect(quoteFromApi(<String, dynamic>{}), isNull);
      expect(quotesFromApiRows([<String, dynamic>{}, 1, 'junk']), isEmpty);
    });
  });

  group('invoiceFromApi', () {
    test('lumpsum completed: type, settled/of from records, zero balance', () {
      final iv = invoiceFromApi({
        'payment_id': 'uuid-p',
        'quotation_number': 'QUO-1',
        'payment_type': 'lumpsum',
        'total_amount': '1800000.00',
        'amount_paid': '1800000.00',
        'amount_remaining': '0.00',
        'status': 'completed',
        'records': [
          {'status': 'paid'},
        ],
      })!;

      expect(iv.id, 'QUO-1');
      expect(iv.quoteId, 'QUO-1');
      expect(iv.type, 'Lump sum');
      expect(iv.total, '₹18L');
      expect(iv.totalNum, 1800000);
      expect(iv.settled, 1);
      expect(iv.of, 1);
      expect(iv.balance, '₹0');
      expect(iv.status, 'completed');
    });

    test('installment invoice with paid amount maps to partial', () {
      final iv = invoiceFromApi({
        'payment_id': 'uuid-p2',
        'quotation_number': 'QUO-2041',
        'customer_id': 'uuid-c',
        'payment_type': 'installment_custom',
        'total_amount': '3650000.00',
        'amount_paid': '1460000.00',
        'amount_remaining': '2190000.00',
        'status': 'active',
        'records': [
          {'status': 'paid'},
          {'status': 'pending'},
          {'status': 'overdue'},
        ],
      })!;

      expect(iv.custId, 'uuid-c');
      expect(iv.type, 'Installments');
      expect(iv.settled, 1);
      expect(iv.of, 3);
      expect(iv.balance, '₹21.9L');
      expect(iv.status, 'partial');
      expect(iv.progress, closeTo(1 / 3, 0.001));
    });

    test('id falls back to payment_id; missing records are 0-safe', () {
      final iv = invoiceFromApi({
        'payment_id': 'uuid-p3',
        'payment_type': 'installment_even',
        'total_amount': '500000.00',
        'amount_paid': '0.00',
        'status': 'active',
      })!;

      expect(iv.id, 'uuid-p3');
      expect(iv.settled, 0);
      expect(iv.of, 0);
      expect(iv.status, 'unpaid');
      expect(iv.progress, 0);

      expect(invoiceFromApi(<String, dynamic>{}), isNull);
    });
  });

  group('paymentRecordFromApi', () {
    test('paid row: amount_paid wins, method display, paid date', () {
      final p = paymentRecordFromApi({
        'record_id': 'uuid-r1',
        'invoice_id': 'uuid-p',
        'customer_id': 'uuid-c',
        'installment_number': 1,
        'amount_expected': '720000.00',
        'amount_paid': '700000.00',
        'due_date': '2026-06-10',
        'paid_date': '2026-06-12',
        'status': 'paid',
        'payment_method': 'bank_transfer',
        'notes': 'Advance · 40%',
      })!;

      expect(p.id, 'uuid-r1');
      expect(p.invId, 'uuid-p');
      expect(p.custId, 'uuid-c');
      expect(p.label, 'Advance · 40%');
      expect(p.amount, '₹7L');
      expect(p.amountNum, 700000);
      expect(p.method, 'Bank transfer');
      expect(p.status, 'paid');
      expect(p.date, '12 Jun 2026');
      expect(p.owner, '');
    });

    test('pending future row: scheduled, Installment N label, dash method', () {
      final p = paymentRecordFromApi({
        'record_id': 'uuid-r2',
        'invoice_id': 'uuid-p',
        'installment_number': 2,
        'amount_expected': '500000.00',
        'amount_paid': '0.00',
        'due_date': '2126-07-01',
        'paid_date': null,
        'status': 'pending',
        'payment_method': null,
        'notes': '',
      })!;

      expect(p.label, 'Installment 2');
      expect(p.amount, '₹5L');
      expect(p.amountNum, 500000);
      expect(p.method, '—');
      expect(p.status, 'scheduled');
      expect(p.date, '1 Jul 2126');
    });

    test('past-due pending row renders as overdue with Overdue date', () {
      final p = paymentRecordFromApi({
        'record_id': 'uuid-r3',
        'amount_expected': '1830000.00',
        'due_date': '2020-06-24',
        'status': 'pending',
      })!;

      expect(p.status, 'overdue');
      expect(p.date, 'Overdue 24 Jun 2020');
      expect(p.amount, '₹18.3L');
    });

    test('cancelled rows are skipped, valid siblings kept', () {
      expect(
        paymentRecordFromApi({'record_id': 'uuid-r4', 'status': 'cancelled'}),
        isNull,
      );

      final list = paymentsFromApiRows([
        {'record_id': 'uuid-a', 'status': 'cancelled'},
        {'record_id': 'uuid-b', 'status': 'paid', 'amount_paid': '100.00'},
        <String, dynamic>{},
        'junk',
      ]);
      expect(list, hasLength(1));
      expect(list.single.id, 'uuid-b');
    });

    test('payment_method codes map onto the UI display strings', () {
      expect(paymentMethodDisplay('bank_transfer'), 'Bank transfer');
      expect(paymentMethodDisplay('upi'), 'UPI');
      expect(paymentMethodDisplay('card'), 'Card');
      expect(paymentMethodDisplay('cash'), 'Cash');
      expect(paymentMethodDisplay('cheque'), 'Cheque');
      expect(paymentMethodDisplay(null), '—');
      expect(paymentMethodDisplay('something_new'), '—');
    });
  });

  group('paymentsFromInvoiceRows (installment-schedule join)', () {
    test('stamps each record invId with the parent quotation_number', () {
      // The invoice header carries the display id; embedded records carry only
      // the parent uuid. After flattening, invId must equal what
      // invoiceFromApi assigns to Invoice.id so the detail-screen join works.
      final invoiceRows = [
        {
          'payment_id': 'pay-uuid-1',
          'quotation_number': 'QTN-2051',
          'total_amount': '300000.00',
          'amount_paid': '100000.00',
          'amount_remaining': '200000.00',
          'status': 'active',
          'payment_type': 'installment_even',
          'records': [
            {
              'record_id': 'rec-1',
              'invoice_id': 'pay-uuid-1',
              'installment_number': 1,
              'amount_expected': '100000.00',
              'amount_paid': '100000.00',
              'status': 'paid',
              'paid_date': '2026-05-01',
              'payment_method': 'upi',
            },
            {
              'record_id': 'rec-2',
              'invoice_id': 'pay-uuid-1',
              'installment_number': 2,
              'amount_expected': '200000.00',
              'due_date': '2026-08-01',
              'status': 'pending',
            },
            {'record_id': 'rec-3', 'status': 'cancelled'},
          ],
        },
      ];

      final invoice = invoiceFromApi(invoiceRows.first)!;
      final payments = paymentsFromInvoiceRows(invoiceRows);

      // Cancelled record dropped; both live records carry the display id.
      expect(payments, hasLength(2));
      expect(payments.every((p) => p.invId == invoice.id), isTrue);
      expect(invoice.id, 'QTN-2051');
      // This is exactly the filter paymentsForInvoiceProvider applies.
      final schedule = payments.where((p) => p.invId == invoice.id).toList();
      expect(schedule.map((p) => p.id), ['rec-1', 'rec-2']);
    });

    test('falls back to payment_id when no quotation_number, tolerates junk', () {
      final rows = paymentsFromInvoiceRows([
        {
          'payment_id': 'pay-9',
          'records': [
            {'record_id': 'r1', 'amount_expected': '500.00', 'status': 'pending'},
          ],
        },
        'garbage',
        <String, dynamic>{},
      ]);
      expect(rows.single.invId, 'pay-9');
    });
  });
}
