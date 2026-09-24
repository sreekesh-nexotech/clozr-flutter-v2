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

    test('accounting change: decimal-string quantity, discount and line order', () {
      // The exact shape `GET /quotations/quotations/{id}/` returns after the
      // accounting-readiness change: quantity is a STRING with three decimals,
      // and the new tax columns ride along as nulls.
      //
      // This is the regression that mattered most. `quantity` used to go
      // through an int-only helper, which returned null for "250.000" and fell
      // through to a `?? 1` default - so EVERY line on EVERY quote rendered
      // "Qty 1". On the dev org 22 of 29 live line items had a quantity other
      // than 1, including lines of 250 and 500 units.
      final q = quoteFromApi({
        'quotation_id': 'uuid-q',
        'quotation_number': 'QTN-00055',
        'total_amount': '89965.00',
        'line_items': [
          {
            'description': 'NexoCRM Starter',
            'quantity': '35.000',
            'unit_price': '1499.00',
            'total_price': '52465.00',
            'line_discount': '0.00',
            'line_no': 2,
            'hsn_sac': null,
            'rate_pct': null,
            'supply_nature': null,
            'product': null,
            'source_package': null,
          },
          {
            'description': 'product 01',
            'quantity': '250.000',
            'unit_price': '150.00',
            'total_price': '37500.00',
            'line_discount': '1200.50',
            'line_no': 1,
          },
        ],
      })!;

      // Sorted by `line_no`, not payload order.
      expect(q.items.map((i) => i.name), ['product 01', 'NexoCRM Starter']);

      final first = q.items.first;
      expect(first.qty, 250.0, reason: 'decimal string must not collapse to 1');
      expect(first.amtNum, 37500);
      expect(first.discount, 1200.5);

      final second = q.items[1];
      expect(second.qty, 35.0);
      expect(second.discount, 0);
    });

    test('accounting change: a fractional quantity survives, zero is not 1', () {
      final q = quoteFromApi({
        'quotation_id': 'uuid-q2',
        'quotation_number': 'QTN-01',
        'total_amount': '1000.00',
        'line_items': [
          {'description': 'Consulting', 'quantity': '2.500', 'unit_price': '400.00', 'total_price': '1000.00'},
          // A genuine zero must read as 0, not fall back to the 1 default -
          // that is why the parser returns null only for *unreadable* input.
          {'description': 'Freebie', 'quantity': '0.000', 'unit_price': '0.00', 'total_price': '0.00'},
          // A deployment sending a JSON number still works.
          {'description': 'Legacy', 'quantity': 4, 'unit_price': '10.00', 'total_price': '40.00'},
          // Unreadable falls back to 1 rather than silently costing nothing.
          {'description': 'Junk', 'quantity': 'n/a', 'unit_price': '10.00', 'total_price': '10.00'},
        ],
      })!;
      expect(q.items[0].qty, 2.5);
      expect(q.items[1].qty, 0.0);
      expect(q.items[2].qty, 4.0);
      expect(q.items[3].qty, 1.0);
    });

    test('the live detail row: server total and per-line total_price', () {
      // As `GET /quotations/quotations/{id}/` serves QTN-00057 on the dev org
      // after the backend started deriving `total_amount`.
      final q = quoteFromApi({
        'quotation_id': '4dddbf6e',
        'quotation_number': 'QTN-00057',
        'total_amount': '25490.00',
        'line_items': [
          {'description': 'NexoCRM Pro', 'quantity': 1, 'unit_price': '14997.00', 'total_price': '14997.00'},
          {'description': 'Analytics Add-on', 'quantity': 1, 'unit_price': '10493.00', 'total_price': '10493.00'},
        ],
      })!;
      expect(q.amountNum, 25490);
      expect(q.items.map((it) => it.amtNum), [14997, 10493]);
    });

    test('a legacy 0.00 total falls back to the line sum; a list row does not', () {
      // Quotes written before the fix still store `total_amount: "0.00"`.
      final legacy = quoteFromApi({
        'quotation_number': 'QTN-00053',
        'total_amount': '0.00',
        'line_items': [
          {'description': 'A', 'quantity': 2, 'unit_price': '100.00', 'total_price': '200.00'},
          {'description': 'B', 'quantity': 1, 'unit_price': '50.00', 'total_price': '50.00'},
        ],
      })!;
      expect(legacy.amountNum, 250);

      // The list projection has no line items, so a zero stays a zero.
      final listRow = quoteFromApi({'quotation_number': 'QTN-00053', 'total_amount': '0.00'})!;
      expect(listRow.amountNum, 0);

      // A non-zero stored total is the server's word, even when it disagrees
      // with the lines (QTN-00022 stores 449997 against 2 × 149999).
      final odd = quoteFromApi({
        'quotation_number': 'QTN-00022',
        'total_amount': '449997.00',
        'line_items': [
          {'description': 'L', 'quantity': 2, 'unit_price': '149999.00', 'total_price': '299998.00'},
        ],
      })!;
      expect(odd.amountNum, 449997);
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
    test('paid row: the CONTRACTED amount is shown, cash kept separately', () {
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
      // The row shows what the instalment is FOR (`amount_expected`), not the
      // cash that arrived. It used to prefer `amount_paid` once the record was
      // paid, so an instalment settled with tax withheld displayed the smaller
      // net figure beside a green "Paid" pill — and the schedule rows stopped
      // summing to the invoice total.
      expect(p.amount, '₹7.2L');
      expect(p.amountNum, 720000);
      // The cash is still available, just not as the headline figure.
      expect(p.paidCashNum, 700000);
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

  group('paymentsFromApiRows (installment-schedule join)', () {
    test('a payment-records row joins its invoice by quotation_number', () {
      // `/quotations/payment-records/` is the confirmed source for "all
      // installments"; each row carries the parent's display id itself, and
      // that is what `invoiceFromApi` assigns to Invoice.id, so the
      // detail-screen join needs no flattening step.
      final invoice = invoiceFromApi({
        'payment_id': 'pay-uuid-1',
        'quotation_number': 'QTN-2051',
        'total_amount': '300000.00',
        'amount_paid': '100000.00',
        'amount_remaining': '200000.00',
        'status': 'active',
        'payment_type': 'installment_even',
      })!;
      final payments = paymentsFromApiRows([
        {
          'record_id': 'rec-1',
          'invoice_id': 'pay-uuid-1',
          'quotation_number': 'QTN-2051',
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
          'quotation_number': 'QTN-2051',
          'installment_number': 2,
          'amount_expected': '200000.00',
          'due_date': '2026-08-01',
          'status': 'pending',
        },
        {'record_id': 'rec-3', 'quotation_number': 'QTN-2051', 'status': 'cancelled'},
        'garbage',
        <String, dynamic>{},
      ]);

      // Cancelled and junk rows dropped; both live records carry the display id.
      expect(payments, hasLength(2));
      expect(invoice.id, 'QTN-2051');
      expect(payments.every((p) => p.invId == invoice.id), isTrue);
      // This is exactly the filter paymentsForInvoiceProvider applies.
      final schedule = payments.where((p) => p.invId == invoice.id).toList();
      expect(schedule.map((p) => p.id), ['rec-1', 'rec-2']);
    });

    test('falls back to the parent uuid when no quotation_number', () {
      final rows = paymentsFromApiRows([
        {'record_id': 'r1', 'invoice_id': 'pay-9', 'amount_expected': '500.00', 'status': 'pending'},
      ]);
      expect(rows.single.invId, 'pay-9');
    });
  });
}
