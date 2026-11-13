import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/crm/application/quote_builder/quote_template_parts.dart';

void main() {
  SpotInputField f(String input) =>
      SpotInputField(key: 'k', label: 'Subsidy amount', input: input);

  test(
      'money / number text is normalised like the webapp (commas and ₹ stripped)',
      () {
    expect(normalizeSpotValue(f('money'), '78,000'), '78000');
    expect(normalizeSpotValue(f('money'), '₹ 1,500.50'), '1500.50');
    expect(normalizeSpotValue(f('number'), 'abc'), isNull);
    expect(normalizeSpotValue(f('text'), '  Site 1 '), 'Site 1');
    expect(normalizeSpotValue(f('money'), ''), '');
  });

  test('invalidSpotNumbers lists only non-numeric money / number fields', () {
    final bad = invalidSpotNumbers([f('money')], {'k': 'abc'});
    expect(bad.map((e) => e.key), ['k']);
    expect(invalidSpotNumbers([f('money')], {'k': '78,000'}), isEmpty);
    expect(invalidSpotNumbers([f('text')], {'k': 'abc'}), isEmpty);
  });
}
