// Phone inputs used to accept anything: no digit filter, no length cap, and
// `+91` only as a placeholder that vanished on the first keystroke. Whatever
// was typed went to the API verbatim, so `9847011001`, `+91 98470 11001` and
// `98470-11001` all became different stored values for one number.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/utils/phone_format.dart';

void main() {
  group('national — the ten digits a field holds', () {
    test('bare ten digits pass through', () {
      expect(PhoneFormat.national('9847011001'), '9847011001');
    });

    test('strips a country code, spaces and punctuation', () {
      for (final raw in [
        '+91 98470 11001',
        '+919847011001',
        '919847011001',
        '98470-11001',
        '(98470) 11001',
      ]) {
        expect(PhoneFormat.national(raw), '9847011001', reason: raw);
      }
    });

    test('strips a trunk zero', () {
      expect(PhoneFormat.national('09847011001'), '9847011001');
    });

    test('a partial number stays partial — never padded or guessed', () {
      expect(PhoneFormat.national('98470'), '98470');
      expect(PhoneFormat.national(''), '');
      expect(PhoneFormat.national(null), '');
    });

    test('an over-long string keeps the last ten', () {
      // Junk is likelier at the front (a stray code) than at the end.
      expect(PhoneFormat.national('0091 98470 11001'), '9847011001');
    });

    test('a landline with an area code still yields ten', () {
      expect(PhoneFormat.national('+91 484 405 8890'), '4844058890');
    });
  });

  group('forApi — what goes on the wire', () {
    test('a complete number becomes +91 and ten digits, no spaces', () {
      // Matches how the backend stores it: "+917045090267".
      expect(PhoneFormat.forApi('9847011001'), '+919847011001');
      expect(PhoneFormat.forApi('+91 98470 11001'), '+919847011001');
    });

    test('re-submitting a stored value does not double the code', () {
      expect(PhoneFormat.forApi('+919847011001'), '+919847011001');
    });

    test('an empty field sends null, not an empty string', () {
      expect(PhoneFormat.forApi(''), isNull);
      expect(PhoneFormat.forApi(null), isNull);
    });

    test('a partial number sends null — better absent than undiallable', () {
      expect(PhoneFormat.forApi('98470'), isNull);
    });
  });

  group('validity', () {
    test('blank is not invalid — phone is optional almost everywhere', () {
      expect(PhoneFormat.isBlank(''), isTrue);
      expect(PhoneFormat.isComplete(''), isFalse);
    });

    test('exactly ten is complete', () {
      expect(PhoneFormat.isComplete('9847011001'), isTrue);
      expect(PhoneFormat.isComplete('984701100'), isFalse);
    });
  });

  group('input formatters', () {
    TextEditingValue type(String s) {
      var value = TextEditingValue.empty;
      for (final f in PhoneFormat.inputFormatters) {
        value = f.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length)),
        );
        s = value.text;
      }
      return value;
    }

    test('letters and symbols are rejected at the keystroke', () {
      // `TextInputType.phone` alone allows these — it only picks the keyboard.
      expect(type('98a4b7*0#1100 1').text, '9847011001');
    });

    test('the eleventh digit cannot be entered', () {
      expect(type('98470110019').text, '9847011001');
    });
  });
}
