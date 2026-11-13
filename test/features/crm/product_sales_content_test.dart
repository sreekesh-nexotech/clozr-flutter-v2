import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/crm/application/product_sales_content.dart';

void main() {
  test('reads the row; empty row is empty', () {
    expect(SalesContent.fromRaw(const {}).isEmpty, isTrue);
    final c = SalesContent.fromRaw({
      'features': ['A', ' ', 'B'],
      'specifications': [
        {'label': 'Weight', 'value': ''},
      ],
      'warranty_summary': '1 year',
      'delivery_lead_time_days': 1,
      'delivery_lead_time_note': 'after advance',
      'brochure': {'media_id': 'm1', 'name': 'Sheet', 'url': 'u'},
    });
    expect(c.features, ['A', 'B']);
    expect(c.specs.single.value, '');
    expect(c.leadTimeLabel, '1 day · after advance');
    expect(c.brochure!.name, 'Sheet');
    expect(c.isEmpty, isFalse);
  });

  test('problems use the webapp wording', () {
    expect(contentProblems(ContentDraft(leadDays: '1.5'))['leadDays'],
        'Enter whole days.');
    expect(
        contentProblems(
            ContentDraft(specs: [(label: '', value: 'x')]))['specs'],
        'Every specification needs a label.');
    expect(
        contentProblems(ContentDraft(
            features: [for (var i = 0; i < 31; i++) 'f$i']))['features'],
        'Up to 30 features.');
    expect(contentProblems(ContentDraft(features: ['ok'])), isEmpty);
  });

  test('patch carries only changed keys and never images / brochure', () {
    final saved = SalesContent.fromRaw({
      'features': ['A'],
      'images': [
        {'media_id': 'i'}
      ]
    });
    expect(contentPatch(saved, ContentDraft.from(saved)), isEmpty);
    final d = ContentDraft.from(saved)
      ..features.add('  Fast   charging ')
      ..leadDays = '14'
      ..warranty = '';
    final p = contentPatch(saved, d);
    expect(p['features'], ['A', 'Fast charging']);
    expect(p['delivery_lead_time_days'], 14);
    expect(p.containsKey('warranty_summary'), isFalse);
    expect(p.containsKey('image_media_ids'), isFalse);
  });
}
