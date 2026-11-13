import 'package:clozrapp/core/utils/phone_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// UI/UX audit #40: stored numbers read "+91 98765 00107".
void main() {
  test('Indian numbers are grouped with the country code', () {
    expect(PhoneFormat.display('+919876500107'), '+91 98765 00107');
    expect(PhoneFormat.display('919876500107'), '+91 98765 00107');
    expect(PhoneFormat.display('9876500107'), '+91 98765 00107');
    expect(PhoneFormat.display('+91 98765-00107'), '+91 98765 00107');
  });
  test('anything ambiguous is shown as stored', () {
    expect(PhoneFormat.display('9198765001102'), '9198765001102');
    expect(PhoneFormat.display('+14155550100'), '+14155550100');
    expect(PhoneFormat.display(''), '');
  });
}
