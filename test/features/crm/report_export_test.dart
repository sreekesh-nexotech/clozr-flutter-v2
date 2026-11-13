import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/crm/application/report_export.dart';

void main() {
  test('the Quotations dataset matches the webapp', () {
    expect(quotationDataset.path, '/report/quotation-export/');
    expect(quotationDataset.columns.length, 14);
    expect(quotationDataset.description,
        'Quotes with totals, validity and payment type');
  });
  test('body keeps dataset order and the file is named with a timestamp', () {
    expect(exportBody(quotationDataset, {'status', 'quotation_id'})['data'],
        ['quotation_id', 'status']);
    expect(columnLabel('final_amount'), 'Final amount');
    expect(exportFileName('Quotations', DateTime(2026, 8, 5, 11, 2, 30)),
        'Quotations_20260805_110230.csv');
  });
}
