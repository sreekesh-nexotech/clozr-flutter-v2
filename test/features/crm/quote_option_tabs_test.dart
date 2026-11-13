import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/crm/application/quote_builder/option_tabs.dart';
import 'package:clozrapp/features/crm/application/quote_builder/quote_builder_draft.dart';
import 'package:clozrapp/features/crm/application/quote_builder/quote_lines.dart';

QuoteFormItem line(String product, {String qty = '1'}) => QuoteFormItem(
    key: 'k-$product',
    kind: LineKind.catalog,
    productId: product,
    name: product,
    qty: qty);

ActiveOption active(List<QuoteFormItem> items, {String title = ''}) =>
    (title: title, items: items, linesDirty: true);

void main() {
  test('Add alternative copies the active option, re-keyed, up to the limit',
      () {
    final a = active([line('p1')], title: 'Basic');
    var tabs = [firstTab(a)];
    tabs = addAlternative(tabs, 0, a, 3);
    expect(tabs.length, 2);
    expect(tabs[1].items.single.productId, 'p1');
    expect(tabs[1].items.single.key, isNot(tabs[0].items.single.key));
    expect(tabs[1].title, isEmpty);
    // the third alternative is refused beyond max
    tabs = addAlternative(tabs, 1, active(tabs[1].items), 3);
    expect(tabs.length, 3);
    expect(addAlternative(tabs, 2, active(tabs[2].items), 3).length, 3);
  });

  test('each tab keeps its own lines when switching', () {
    final a = active([line('p1')]);
    var tabs = addAlternative([firstTab(a)], 0, a, 3);
    // active option B changes its product
    final b = active([line('p2')]);
    tabs = stashActive(tabs, 1, b);
    expect(tabs[0].items.single.productId, 'p1');
    expect(tabs[1].items.single.productId, 'p2');
  });

  test('removing re-labels the rest and the last option cannot be removed', () {
    final a = active([line('p1')]);
    var tabs = addAlternative(addAlternative([firstTab(a)], 0, a, 3), 1, a, 3);
    final r = removeOption(tabs, 2, active(tabs[2].items), 2);
    expect(r.tabs.length, 2);
    expect(r.active, 1);
    expect(optionLabel(r.tabs.length - 1), 'B');
    final single = removeOption([firstTab(a)], 0, a, 0);
    expect(single.tabs.length, 1);
    expect(primaryAfterRemove(1, 1), 0);
    expect(primaryAfterRemove(2, 0), 1);
  });

  test('an empty alternative blocks the create with the option named', () {
    final a = active([line('p1')]);
    var tabs = addAlternative([firstTab(a)], 0, a, 3);
    tabs = stashActive(tabs, 1, active([QuoteFormItem.blank()]));
    final problems = optionProblems(tabs, false);
    expect(problems.single.label, 'B');
    expect(problems.single.problem, 'empty');
    expect(
        optionBlockReason(problems), 'Option B: add at least one line item.');
    expect(optionBlockReason(const []), isNull);
  });

  test('a new group posts shared fields once + options + primary_index', () {
    final a = active([line('p1')], title: 'Basic');
    var tabs = addAlternative([firstTab(a)], 0, a, 3);
    tabs = stashActive(tabs, 1, active([line('p2')], title: 'Premium'));
    final body = toNewGroupJson({
      'template': 't1',
      'lead': 'L1',
      'quotation_title': 'ignored',
      'line_items': [
        {'x': 1}
      ],
      'payment_type': 'lumpsum',
    }, tabs, 1);
    expect(body.containsKey('line_items'), isFalse);
    expect(body.containsKey('quotation_title'), isFalse);
    expect(body['template'], 't1');
    expect(body['primary_index'], 1);
    final options = body['options'] as List;
    expect(options.length, 2);
    expect((options[0] as Map)['quotation_title'], 'Basic');
    expect((options[1] as Map)['line_items'], isNotEmpty);
  });

  test(
      'a group edit keeps untouched options\' saved lines and only sends real changes',
      () {
    final saved = [
      SavedQuote(id: 'q1', title: 'A', lines: const [
        {
          'description': 'x',
          'quantity': '1',
          'unit_price': '10',
          'product': 'p1'
        }
      ]),
      SavedQuote(id: 'q2', title: 'B', lines: const [
        {
          'description': 'y',
          'quantity': '1',
          'unit_price': '20',
          'product': 'p2'
        }
      ]),
    ];
    var tabs = tabsFromOptions(saved);
    expect(optionsChanged(tabs, saved), isFalse);
    expect(optionProblems(tabs, true), isEmpty);
    final inputs = toOptionInputs(tabs, true);
    expect(inputs[0].containsKey('line_items'), isFalse);
    expect(inputs[0]['quotation_id'], 'q1');
    tabs = stashActive(
        tabs, 1, (title: 'B', items: [line('p3')], linesDirty: true));
    expect(optionsChanged(tabs, saved), isTrue);
    expect(toOptionInputs(tabs, true)[1]['line_items'], isNotEmpty);
    final patch = toGroupPatchJson(
        {'template': 'x', 'status_id': 's', 'notes': 'n'}, tabs,
        optionsDiffer: true, primaryQuotationId: 'q2');
    expect(
        patch.keys, containsAll(['notes', 'options', 'primary_quotation_id']));
    expect(patch.containsKey('template'), isFalse);
    expect(patch.containsKey('status_id'), isFalse);
  });
}
