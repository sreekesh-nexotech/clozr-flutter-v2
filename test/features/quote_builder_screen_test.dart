import 'package:clozrapp/features/accounting/application/providers/accounting_providers.dart';
import 'package:clozrapp/features/crm/application/providers/products_providers.dart';
import 'package:clozrapp/features/crm/application/providers/quote_builder_providers.dart';
import 'package:clozrapp/features/crm/application/quote_builder/quote_builder_draft.dart';
import 'package:clozrapp/features/crm/application/quote_builder/quote_tax.dart';
import 'package:clozrapp/features/crm/application/quote_builder/quote_template_parts.dart';
import 'package:clozrapp/features/crm/domain/entities/product.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/quote_builder_remote_ds.dart';
import 'package:clozrapp/features/crm/presentation/screens/add_quote_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Smoke tests for the quote builder screen: New / Edit / locked titles, the
/// footer hints and the read-only notice — rendered with every server call
/// faked, so layout errors surface here rather than on a device.

class _FakeDs implements QuoteBuilderRemoteDataSource {
  _FakeDs(this.quote);
  final Map<String, dynamic>? quote;

  @override
  Future<SavedQuote> fetchQuote(String id) async => SavedQuote.fromJson(quote!);

  @override
  Future<TaxPreview> previewTax(Map<String, dynamic> body) async => TaxPreview.fromJson({
        'taxable_total': '100.00',
        'grand_total': '118.00',
        'tax_summary': {
          'supply': 'INTRA',
          'taxable_total': '100.00',
          'cgst': '9.00',
          'sgst': '9.00',
          'grand_total': '118.00',
        },
        'line_items': [],
      });

  @override
  Future<PartyOption?> partyById(QuoteFor kind, String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, String location, {Map<String, dynamic>? quote}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: location, routes: [
    GoRoute(path: '/quotes/add', builder: (_, __) => const Scaffold(body: AddQuoteScreen())),
    GoRoute(path: '/quotes/edit', builder: (_, __) => const Scaffold(body: AddQuoteScreen())),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      quoteBuilderDsProvider.overrideWithValue(_FakeDs(quote)),
      quoteBuilderTemplatesProvider.overrideWith((ref) async => const [
            QuoteTemplateOption(id: 't1', name: 'Solar Quote 01', isDefault: true),
            QuoteTemplateOption(id: 't2', name: 'Payment Receipt', isDefault: true, category: 'receipt'),
          ]),
      quoteTaxDefaultsProvider.overrideWith((ref) async => const QuoteTaxDefaults(amountsAre: 'EXCLUSIVE')),
      quoteClauseLibraryProvider.overrideWith((ref) async => const [
            LibraryClause(id: 'v', title: 'Validity', isMandatory: true),
            LibraryClause(id: 'p', title: 'Payment Terms', position: 1),
          ]),
      quoteDefaultStatusProvider.overrideWith((ref) async => 's1'),
      quoteTemplateFieldsProvider.overrideWith((ref, id) async => const []),
      quoteTemplateConfigProvider.overrideWith((ref, id) async => const TemplateLayoutConfig()),
      productsProvider.overrideWith((ref) async => const <Product>[]),
      gstStatesProvider.overrideWith((ref) async => const []),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp.router(routerConfig: router),
    ),
  ));
  await tester.pumpAndSettle(const Duration(milliseconds: 600));
}

Map<String, dynamic> _quote({bool locked = false}) => {
      'quotation_id': 'q1',
      'quotation_number': 'QTN-00028',
      'quotation_title': '',
      'template': 't1',
      'template_name': 'Solar Quote 01',
      'lead': 'l1',
      'lead_name': 'Arjun Roy - Upselling 01',
      'payment_type': 'lumpsum',
      'num_installments': null,
      'billing_period_days': 30,
      'valid_until': '2026-11-21',
      'due_date': null,
      'notes': '',
      'terms_and_conditions': '',
      'contract_ref': 'PO-UAT-',
      'field_values': {},
      'amounts_are': 'EXCLUSIVE',
      'place_of_supply_state_code': null,
      'is_locked': locked,
      'discount_pct': '10.00',
      'clauses': [
        {'quotation_clause_id': 'qc1', 'clause_id': 'v', 'title': 'Validity', 'is_mandatory': true, 'position': 0},
      ],
      'line_items': [
        {'line_no': 1, 'product': 'p1', 'description': 'Panel', 'quantity': '1.000', 'unit_price': '9000.000000', 'total_price': '9000.00'},
      ],
      'tax_summary': {'supply': 'INTRA', 'taxable_total': '9000.00', 'cgst': '810.00', 'sgst': '810.00', 'grand_total': '10620.00'},
    };

void main() {
  testWidgets('new quote: party first, the default quote template, clause defaults', (tester) async {
    await _pump(tester, '/quotes/add');
    expect(find.text('New quote'), findsOneWidget);
    expect(find.text('Solar Quote 01'), findsOneWidget); // not the receipt family's default
    expect(find.text('Choose who the quote is for.'), findsOneWidget);
    expect(find.text('Converted leads are quoted from their customer.'), findsOneWidget);
    expect(find.text('Create quote'), findsOneWidget);
    final note = find.text('GST shown is an estimate; the tax invoice from Accounting carries the final figures.');
    await tester.scrollUntilVisible(note, 300, scrollable: find.byType(Scrollable).first);
    expect(note, findsOneWidget);
    expect(find.text('CGST (estimate)'), findsNothing); // no priced lines yet → no GST rows
    await tester.scrollUntilVisible(find.text('Validity'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Validity'), findsOneWidget);
  });

  testWidgets('customer mode shows its hint', (tester) async {
    await _pump(tester, '/quotes/add');
    await tester.tap(find.text('Customer'));
    await tester.pumpAndSettle();
    expect(
        find.text('The quote is linked to the customer’s lead (its source lead, or its latest upsell lead).'), findsOneWidget);
  });

  testWidgets('edit quote: titled with its number, saved discount shown', (tester) async {
    await _pump(tester, '/quotes/edit?id=q1', quote: _quote());
    expect(find.text('Edit quote QTN-00028'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Discount (as last saved)'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('10.00%'), findsOneWidget);
  });

  testWidgets('a sent quote opens read-only with Close only', (tester) async {
    await _pump(tester, '/quotes/edit?id=q1', quote: _quote(locked: true));
    expect(find.text('Quote QTN-00028'), findsOneWidget);
    expect(find.text(lockedCopy), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Save changes'), findsNothing);
  });

  testWidgets('a typed line: price without description is called out; Amounts-are flip asks Convert / Keep',
      (tester) async {
    await _pump(tester, '/quotes/add');
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Add free-text line'), 200, scrollable: list);
    await tester.ensureVisible(find.text('Add free-text line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add free-text line'));
    await tester.pumpAndSettle();
    // The new free-text row's price box.
    await tester.enterText(find.widgetWithText(TextField, '0.00').last, '500');
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Describe every typed line — a line without a product needs a description.'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(TextField, 'Describe the item or service').last);
    await tester.enterText(find.widgetWithText(TextField, 'Describe the item or service').last, 'Installation');
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Choose who the quote is for.'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Tax inclusive'), 200, scrollable: list);
    await tester.ensureVisible(find.text('Tax inclusive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tax inclusive'));
    await tester.pumpAndSettle();
    expect(find.text('Change how amounts are entered?'), findsOneWidget);
    expect(find.text('Convert prices (total stays)'), findsOneWidget);
    expect(find.text('Keep prices (total changes)'), findsOneWidget);
    expect(find.text('RESULT'), findsOneWidget);
  });
}
