import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/crm/application/quote_lifecycle.dart';

void main() {
  test('a generated document row maps, with the outdated flag and meta line',
      () {
    final d = GeneratedDoc.fromJson({
      'generated_document_id': 'd1',
      'document_number': 'OC/26-27/0002',
      'title': 'Order Confirmation — QTN-1',
      'template_name': 'Order Confirmation',
      'file_url_signed': 'https://x/y.pdf',
      'size_bytes': 22771,
      'created_by_name': 'Neeraja',
      'quotation_number': 'QTN-1',
      'is_stale': true,
      'field_values': {'remarks': 'r'},
    });
    expect(d.isStale, isTrue);
    expect(d.fileUrl, 'https://x/y.pdf');
    expect(d.numberSuffix, 'OC/26-27/0002'); // title lacks the number
    expect(generatedDocMeta(d, (_) => ''), 'Neeraja · 22 KB · quote QTN-1');
  });

  test('regenerate prefills stored values over the template defaults', () {
    const t = DocTemplate(id: 't', name: 'OC', fields: [
      DocTemplateField(
          key: 'po', label: 'PO', type: 'text', defaultValue: 'DEF'),
      DocTemplateField(key: 'on', label: 'On', type: 'date'),
      DocTemplateField(
          key: 'x', label: 'X', type: 'text', defaultValue: 'keep'),
    ]);
    expect(storedDocumentValues(t, {'po': 'PO-9', 'on': '2026-11-30T00:00:00'}),
        {'po': 'PO-9', 'on': '2026-11-30', 'x': 'keep'});
  });

  test('quote-only templates and the lead source reach the body', () {
    final list = DocTemplate.listFrom({
      'results': [
        {
          'template_id': 'a',
          'template_name': 'Proposal Document',
          'requires_quotation': true
        },
        {'template_id': 'b', 'template_name': 'Delivery Challan'},
      ]
    });
    expect(list.map((e) => e.requiresQuotation), [true, false]);
    final body = generateDocumentBodyFor(list[1], const {}, leadId: 'L1');
    expect(body['lead_id'], 'L1');
    expect(body.containsKey('quotation_id'), isFalse);
  });
}
