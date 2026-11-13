import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/crm/application/lead_deal_fields.dart';

void main() {
  test('fields are grouped like the webapp', () {
    expect(dealGroupOf('budget_min'), DealGroup.deal);
    expect(dealGroupOf('billing_city'), DealGroup.billing);
    expect(dealGroupOf('gstin'), DealGroup.billing);
    expect(dealGroupOf('payment_preference'), DealGroup.commercial);
    expect(dealGroupOf('consent_notice_version'), DealGroup.consent);
    expect(dealGroupOf('lead_name'), isNull);
  });

  test('values read the way the webapp shows them', () {
    expect(formatDealValue('budget_min', '100000.00'), contains('1,00,000'));
    expect(formatDealValue('decision_maker', true), 'Yes');
    expect(formatDealValue('decision_maker', false), 'No');
    expect(formatDealValue('decision_maker', null), '');
    expect(formatDealValue('designation', ''), '');
    expect(
        formatDealValue('billing_state_code', '32',
            stateName: (c) => 'Kerala ($c)'),
        'Kerala (32)');
  });

  test('wire conversion', () {
    expect(toDealWire(DealKind.money, '1,50,000').value, '150000.00');
    expect(toDealWire(DealKind.money, '150000.5').value, '150000.50');
    expect(toDealWire(DealKind.money, 'abc').ok, isFalse);
    expect(toDealWire(DealKind.money, 'abc').error, moneyInputError);
    expect(toDealWire(DealKind.money, '  ').value, isNull);
    expect(toDealWire(DealKind.tristate, 'true').value, true);
    expect(toDealWire(DealKind.tristate, '').value, isNull);
    expect(toDealWire(DealKind.gstin, ' 32aaacr5055k1zg ').value,
        '32AAACR5055K1ZG');
  });

  test('consent line is absent without a stamp', () {
    expect(consentLine(null, null), isNull);
    expect(consentLine(null, 3), '— · notice v3');
  });
}
