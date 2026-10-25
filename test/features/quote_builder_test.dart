import 'package:clozrapp/features/crm/application/quote_builder/quote_builder_draft.dart';
import 'package:clozrapp/features/crm/application/quote_builder/quote_lines.dart';
import 'package:clozrapp/features/crm/application/quote_builder/quote_tax.dart';
import 'package:clozrapp/features/crm/application/quote_builder/quote_template_parts.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/quote_builder_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

/// The quote builder's pure rules, ported from the webapp builder — line
/// validation, the create body (title + validity are sent) and the edit diff
/// (only changed keys).

QuoteFormItem _catalog({String qty = '1', String rate = '', bool touched = false, String id = 'p1'}) =>
    QuoteFormItem.blank().withProduct(id, productName: 'Solar Panel', package: false).copyWith(
          qty: qty,
          rate: rate,
          priceTouched: touched,
        );

QuoteFormItem _free({String name = 'Install', String qty = '1', String rate = '100', String hsn = '', String gst = ''}) =>
    QuoteFormItem.blank(LineKind.free).copyWith(name: name, qty: qty, rate: rate, hsnSac: hsn, gstRate: gst);

String _block(List<QuoteFormItem> items, {bool past = false}) => blockReason(
      items: items,
      validityInPast: past,
      recurringWithSubscription: false,
      hasAmountsAre: true,
      attemptedSave: false,
      missingTemplateField: false,
    );

void main() {
  group('line validation (QT-015)', () {
    test('quantity: zero and over one crore are refused, 4 decimals round to 3', () {
      expect(lineProblem(_catalog(qty: '0')), LineProblem.qty);
      expect(lineProblem(_catalog(qty: '10000001')), LineProblem.qty);
      expect(lineProblem(_catalog(qty: '1.2345')), isNull);
      expect(toQty('1.2345'), 1.235);
      expect(_block([_catalog(qty: '0')]), 'Enter a quantity (at most 1,00,00,000) for every line.');
    });

    test('unit price: commas / ₹ are stripped, 7 decimals and > ₹100 crore refused', () {
      expect(lineProblem(_catalog(rate: '1,00,000.1234567', touched: true)), LineProblem.price);
      expect(lineProblem(_catalog(rate: '₹ 1,00,000.123456', touched: true)), isNull);
      expect(lineProblem(_catalog(rate: '1000000001', touched: true)), LineProblem.price);
      expect(_block([_catalog(rate: 'abc', touched: true)]),
          'Enter a unit price (up to 6 decimals, at most ₹100 crore) for every typed line.');
    });

    test('an untouched catalog line needs no price (the server prices it)', () {
      expect(lineProblem(_catalog()), isNull);
    });

    test('a typed line with a price but no description is flagged, not dropped', () {
      final line = _free(name: '');
      expect(lineProblem(line), LineProblem.description);
      expect(_block([line]), 'Describe every typed line — a line without a product needs a description.');
    });

    test('typed line tax: HSN 4–8 digits, GST rate 0–100', () {
      expect(freeLineTaxProblem(_free(hsn: '12')), FreeTaxProblem.hsn);
      expect(freeLineTaxProblem(_free(hsn: '998313', gst: '101')), FreeTaxProblem.rate);
      expect(lineProblem(_free(hsn: '998313', gst: '18')), isNull);
      expect(_block([_free(hsn: '12')]), 'Check the typed lines’ tax: HSN/SAC is 4 to 8 digits, GST rate 0–100%.');
    });

    test('quantity outranks price outranks validity in the footer hint', () {
      expect(_block([_catalog(qty: '0'), _catalog(rate: 'x', touched: true)], past: true),
          'Enter a quantity (at most 1,00,00,000) for every line.');
      expect(_block([_catalog()], past: true), 'The validity date can’t be in the past.');
    });
  });

  group('recurring charges (QT-021)', () {
    test('charge problems in the web wording', () {
      expect(chargeProblem(const LineCharge(chargeType: ChargeType.recurring)), 'Choose how often it is billed.');
      expect(
          chargeProblem(const LineCharge(chargeType: ChargeType.recurring, billingPeriod: 'custom_days', billingPeriodDays: 400)),
          'A custom period is 1 to 366 days.');
      expect(chargeProblem(const LineCharge(chargeType: ChargeType.recurring, billingPeriod: 'month', termPeriods: 121)),
          'The term is 1 to 120 periods (blank = until cancelled).');
      expect(chargeProblem(const LineCharge(chargeType: ChargeType.recurring, billingPeriod: 'month', termPeriods: 12)), isNull);
    });

    test('subscription with a recurring line is refused', () {
      expect(
        blockReason(
          items: [_catalog()],
          validityInPast: false,
          recurringWithSubscription: true,
          hasAmountsAre: true,
          attemptedSave: false,
          missingTemplateField: false,
        ),
        'Recurring lines bill on their own schedule: choose lump sum or instalments for the one-time part.',
      );
    });
  });

  group('line write rows', () {
    test('an untouched catalog line omits unit_price; a pinned one sends it cleaned', () {
      final rows = toLineRows([_catalog(qty: '2'), _catalog(id: 'p2', rate: '9,000', touched: true)]);
      expect(rows[0], {'description': 'Solar Panel', 'quantity': '2', 'product_id': 'p1'});
      expect(rows[1]['unit_price'], '9000');
    });

    test('use the catalog price un-pins the line', () {
      final reset = _catalog(rate: '9000', touched: true).withCatalogPrice();
      expect(sendsOwnPrice(reset), isFalse);
      expect(toLineRows([reset]).single.containsKey('unit_price'), isFalse);
    });

    test('a typed line sends its own HSN and GST rate', () {
      final row = toLineRows([_free(hsn: '998313', gst: '18', qty: '2.5')]).single;
      expect(row['hsn_sac'], '998313');
      expect(row['rate_pct'], '18');
      expect(row['quantity'], '2.5');
      expect(row['unit_price'], '100');
    });

    test('a recurring line sends its charge keys', () {
      final line = _catalog().copyWith(
          charge: const LineCharge(chargeType: ChargeType.recurring, billingPeriod: 'month', termPeriods: 12));
      expect(toLineRows([line]).single, containsPair('billing_period', 'month'));
    });
  });

  group('price display', () {
    test('server decimals are trimmed without changing the value', () {
      expect(formatUnitPriceInput('1000.000000'), '1000');
      expect(formatUnitPriceInput('999.500000'), '999.50');
      expect(formatUnitPriceInput('846.610169'), '846.610169');
    });

    test('2 dp unless the extra decimals change the amount', () {
      expect(displayUnitPrice('18698.410000', 9), '18698.41');
      expect(displayUnitPrice('846.610169', 1000), '846.610169');
    });

    test('Indian grouping', () {
      expect(groupedUnitPrice('14160.00'), '14,160.00');
      expect(groupedUnitPrice('100000.5'), '1,00,000.50');
    });
  });

  group('create body (QT-013 / QT-020)', () {
    const ctx = BuilderWriteContext(templateId: 't1', amountsAre: 'EXCLUSIVE', statusId: 's1');

    test('title and valid_until are sent — the old form dropped both', () {
      final draft = BuilderDraft.empty(leadId: 'lead-1').copyWith(
        title: 'Rooftop 5 kW',
        validUntil: '2026-11-23',
        items: [_catalog(qty: '2')],
      );
      final json = toNewQuoteJson(draft, ctx);
      expect(json['quotation_title'], 'Rooftop 5 kW');
      expect(json['valid_until'], '2026-11-23');
      expect(json['lead'], 'lead-1');
      expect(json.containsKey('customer'), isFalse);
      expect(json['template'], 't1');
      expect(json['status_id'], 's1');
      expect(json['amounts_are'], 'EXCLUSIVE');
      expect(json['payment_type'], 'lumpsum');
      // Untouched clause list / sections are left to the server's defaults.
      expect(json.containsKey('clauses'), isFalse);
      expect(json.containsKey('sections'), isFalse);
    });

    test('customer mode sends only the customer', () {
      final draft = BuilderDraft.empty(customerId: 'c1').copyWith(items: [_catalog()]);
      final json = toNewQuoteJson(draft, ctx);
      expect(json['customer'], 'c1');
      expect(json.containsKey('lead'), isFalse);
    });

    test('an even split sends its instalment count; template fields and clauses ride along', () {
      final draft = BuilderDraft.empty(leadId: 'l').copyWith(
        payType: 'installment_even',
        installments: '3',
        items: [_catalog()],
        fieldEdits: {'po': 'PO-1'},
        spotValues: {'ship_to_name': ' Site A ', 'your_ref': ' '},
        clauseRows: const [ClauseRow(key: 'k', title: 'Validity', clauseId: 'cl1')],
      );
      final json = toNewQuoteJson(
          draft,
          const BuilderWriteContext(
              templateId: 't1',
              amountsAre: 'EXCLUSIVE',
              fields: [TemplateField(key: 'po', label: 'PO', type: TemplateFieldType.text)]));
      expect(json['num_installments'], 3);
      expect(json['billing_period_days'], isNull);
      expect(json['field_values'], {'po': 'PO-1', 'ship_to_name': 'Site A'});
      expect(json['clauses'], [
        {'clause_id': 'cl1'}
      ]);
    });

    test('a past validity date is refused; an unchanged saved one is left alone', () {
      expect(validUntilInPast('2026-10-23', '', '2026-10-24'), isTrue);
      expect(validUntilInPast('2026-10-24', '', '2026-10-24'), isFalse);
      expect(validUntilInPast('2026-10-01', '2026-10-01', '2026-10-24'), isFalse);
      expect(validUntilInPast('', '', '2026-10-24'), isFalse);
    });
  });

  group('edit diff (QT-024 / QT-026)', () {
    final saved = SavedQuote.fromJson({
      'quotation_id': 'q1',
      'quotation_number': 'QTN-00028',
      'quotation_title': '',
      'template': 't1',
      'lead': 'l1',
      'lead_name': 'Arjun Roy',
      'payment_type': 'lumpsum',
      'num_installments': null,
      'billing_period_days': 30,
      'valid_until': '2026-11-21',
      'due_date': null,
      'notes': '',
      'terms_and_conditions': '',
      'amounts_are': 'EXCLUSIVE',
      'place_of_supply_state_code': null,
      'contract_ref': 'PO-UAT-',
      'field_values': {},
      'line_items': [
        {'line_no': 1, 'product': 'p1', 'description': 'Panel', 'quantity': '9.000', 'unit_price': '18698.410000'},
      ],
      'discount_pct': '10.00',
    });
    const ctx = BuilderWriteContext(templateId: 't1', amountsAre: 'EXCLUSIVE');

    test('an untouched quote has nothing to save', () {
      expect(toQuoteUpdateJson(BuilderDraft.fromQuote(saved), saved, ctx), isEmpty);
    });

    test('a changed title sends only the title', () {
      final draft = BuilderDraft.fromQuote(saved).copyWith(title: 'Phase 2');
      expect(toQuoteUpdateJson(draft, saved, ctx), {'quotation_title': 'Phase 2'});
    });

    test('valid until can be changed but not cleared', () {
      final changed = BuilderDraft.fromQuote(saved).copyWith(validUntil: '2026-12-01');
      expect(toQuoteUpdateJson(changed, saved, ctx), {'valid_until': '2026-12-01'});
      final cleared = BuilderDraft.fromQuote(saved).copyWith(validUntil: '');
      expect(toQuoteUpdateJson(cleared, saved, ctx), isEmpty);
    });

    test('saved lines keep their stored price; edited lines are re-sent', () {
      final draft = BuilderDraft.fromQuote(saved);
      expect(draft.items.single.priceTouched, isTrue);
      expect(draft.items.single.rate, '18698.41');
      final edited = draft.copyWith(items: [draft.items.single.copyWith(qty: '10')], linesDirty: true);
      final patch = toQuoteUpdateJson(edited, saved, ctx);
      expect(patch.keys, ['line_items']);
      expect((patch['line_items'] as List).single['unit_price'], '18698.41');
    });

    test('an Amounts-are flip with untouched lines asks the server to convert', () {
      final draft = BuilderDraft.fromQuote(saved).copyWith(amountsAreChoice: 'INCLUSIVE', serverFlip: 'convert');
      final patch = toQuoteUpdateJson(
          draft, saved, const BuilderWriteContext(templateId: 't1', amountsAre: 'INCLUSIVE'));
      expect(patch, {'amounts_are': 'INCLUSIVE', 'price_conversion': 'convert'});
    });

    test('org-hidden fields are listed and never written', () {
      final hiddenQuote = SavedQuote.fromJson({
        'quotation_id': 'q2',
        'template': 't1',
        'line_items': [],
        'notes': '',
        'terms_and_conditions': '',
        'field_values': {},
        'valid_until': '2026-11-21',
        'due_date': null,
        'num_installments': null,
        'billing_period_days': null,
        'payment_type': 'lumpsum',
        'amounts_are': 'EXCLUSIVE',
      });
      final hidden = hiddenFields(hiddenQuote);
      expect(hidden, {'quotation_title', 'contract_ref'});
      expect(hiddenFieldsNotice(hidden),
          'Not included in your workspace’s quote fields, so not editable here: Quote title, Contract reference.');
      final draft = BuilderDraft.fromQuote(hiddenQuote).copyWith(title: 'x', contractRef: 'y');
      expect(toQuoteUpdateJson(draft, hiddenQuote, ctx), isEmpty);
    });

    test('approval state and discount are read from the response', () {
      final pending = SavedQuote.fromJson({'quotation_id': 'q', 'approval_status': 'PENDING', 'discount_pct': '20'});
      expect(pending.approvalIsPending, isTrue);
      expect(pct2(pending.discountPct), '20.00%');
    });
  });

  group('totals (QT-017)', () {
    test('intra-state shows CGST + SGST, inter-state IGST, round off when non-zero', () {
      final intra = TaxSummary.fromJson({
        'supply': 'INTRA',
        'taxable_total': '100.00',
        'cgst': '9.00',
        'sgst': '9.00',
        'igst': '0.00',
        'cess': '0.00',
        'round_off': '0.00',
        'grand_total': '118.00',
      });
      expect(taxTotalsRows(intra).map((r) => r.label), ['Sub-total', 'CGST', 'SGST']);
      final inter = TaxSummary.fromJson({
        'supply': 'INTER',
        'taxable_total': '100.00',
        'igst': '18.00',
        'round_off': '0.31',
        'grand_total': '118.31',
      });
      expect(taxTotalsRows(inter).map((r) => r.label), ['Sub-total', 'IGST', 'Round off']);
    });

    test('priced lines map back onto their rows, a package owning its parts', () {
      final rows = [const PreviewRowRef('a', ''), const PreviewRowRef('b', 'pkg'), const PreviewRowRef('c', '')];
      final lines = [
        PricedLine.fromJson({'unit_price': '1', 'total_price': '1'}),
        PricedLine.fromJson({'unit_price': '2', 'total_price': '2', 'source_package_id': 'pkg'}),
        PricedLine.fromJson({'unit_price': '3', 'total_price': '3', 'source_package_id': 'pkg'}),
        PricedLine.fromJson({'unit_price': '4', 'total_price': '4'}),
      ];
      final m = mapPreviewLines(rows, lines);
      expect(m['b']!.length, 2);
      expect(m['c']!.single.unitPrice, '4');
    });

    test('a half-typed line keeps the last preview instead of pricing it', () {
      const ctx = PreviewContext(isEdit: false, linesDirty: false, savedMode: '');
      expect(livePreviewRequest(ctx, [_catalog(qty: '0')], 'EXCLUSIVE', null), isNull);
      final req = livePreviewRequest(ctx, [_catalog()], 'EXCLUSIVE', null)!;
      expect(req.body['amounts_are'], 'EXCLUSIVE');
      expect(req.body['line_items'], hasLength(1));
    });
  });

  group('clauses (QT-023)', () {
    const today = '2026-10-24';
    const library = [
      LibraryClause(id: 'v', title: 'Validity', isMandatory: true, position: 0),
      LibraryClause(id: 'p', title: 'Payment Terms', position: 1),
      LibraryClause(id: 'f', title: 'Future', effectiveDate: '2027-01-01', position: 2),
      LibraryClause(id: 'q', title: 'Quote family', defaultFamilies: ['quote'], position: 3),
    ];

    test('defaults: unscoped mandatory + quote family; not-yet-effective ones excluded', () {
      expect(defaultClauseRows(library, const {}, today).map((r) => r.clauseId), ['v', 'q']);
      expect(addableClauses(library, defaultClauseRows(library, const {}, today), today).map((c) => c.id), ['p']);
    });

    test('a preloaded mandatory clause cannot be removed; an added one can', () {
      var rows = defaultClauseRows(library, const {}, today);
      expect(removeClause(rows, 'default:v').length, rows.length);
      rows = addLibraryClause(rows, library[1]);
      expect(removeClause(rows, 'added:p').map((r) => r.clauseId), ['v', 'q']);
      expect(moveClause(rows, 'added:p', -1).map((r) => r.clauseId), ['v', 'p', 'q']);
      expect(toClauseWrites(rows).first, {'clause_id': 'v'});
    });

    test('clause bodies render as plain text', () {
      expect(clauseText('<p>Valid&nbsp;until &amp; including</p><p>the date</p>'), 'Valid until & including\nthe date');
    });
  });

  group('template fields + sections (QT-022)', () {
    test('a required blank field is missing; checkboxes never are', () {
      const req = TemplateField(key: 'po', label: 'PO', type: TemplateFieldType.text, required: true);
      const box = TemplateField(key: 'ok', label: 'OK', type: TemplateFieldType.boolean, required: true);
      expect(isFieldMissing(req, ''), isTrue);
      expect(isFieldMissing(box, false), isFalse);
    });

    test('server-filled keys get no input', () {
      final fields = templateFieldsFromDetail({
        'field_definitions': [
          {'field_key': 'notes', 'field_type': 'text'},
          {'field_key': 'po', 'field_label': 'PO', 'field_type': 'Dropdown', 'options': ['A']},
        ],
      });
      final editable = editableTemplateFields(fields);
      expect(editable.single.key, 'po');
      expect(editable.single.type, TemplateFieldType.select);
    });

    test('a mandatory heading left empty is reported in the web wording', () {
      const h = SectionHeading(id: 'h', label: 'Warranty', isMandatory: true, options: [SectionOption(id: 'o', title: 'Std')]);
      final missing = missingMandatoryHeadings(const [h], const []);
      expect(mandatoryHeadingsNotice(missing),
          '“Warranty” is a mandatory heading — choose an option before the quote is sent.');
      expect(missingMandatoryHeadings(const [h], const [SectionPick('h', 'o')]), isEmpty);
    });

    test('spot inputs: required blanks are reported', () {
      const f = SpotInputField(key: 'ref', label: 'Your reference', required: true, needsInput: true);
      expect(missingRequiredSpot(const [f], const {}).single.label, 'Your reference');
      expect(missingRequiredSpot(const [f], const {'ref': 'RFQ-1'}), isEmpty);
    });
  });

  group('party rows (QT-014)', () {
    test('upsell leads are labelled; the LD reference is the sub-line', () {
      final o = QuoteBuilderRemoteDataSource.leadOption(
          {'lead_id': 'uuid-1', 'lead_name': 'Malabar Spices Co – Upsell', 'is_upsell': true, 'reference': 'LD-0025'});
      expect(o.label, 'Malabar Spices Co – Upsell · upsell');
      expect(o.sub, 'LD-0025');
    });
  });

  test('payment types are labelled like the web (milestone-based)', () {
    expect(payTypeLabel('installment_custom'), 'Milestone-based');
    expect(paymentFlags('installment_even').installments, isTrue);
    expect(paymentFlags('lumpsum').billing, isFalse);
  });
}
