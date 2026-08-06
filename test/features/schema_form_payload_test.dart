// The schema form sent every non-choice field as its text box's raw string. On
// a task that meant an untouched `duration` arrived as `""` and the API
// rejected the whole save:
//   {"duration": ["A valid integer is required."]}
// Verified against the live API: `""` → 400, `null` → 200, `45` → 200.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/record_rows.dart';

void main() {
  group('numbers', () {
    test('an empty box clears the field instead of sending ""', () {
      // The exact payload that produced the 400.
      expect(schemaWriteValue('integer', ''), isNull);
      expect(schemaWriteValue('integer', '   '), isNull);
      expect(schemaWriteValue('integer', ''), isNot(''));
    });

    test('a filled box is sent as a number, not its text', () {
      expect(schemaWriteValue('integer', '45'), 45);
      expect(schemaWriteValue('integer', '45'), isA<int>());
      expect(schemaWriteValue('decimal', '12.5'), 12.5);
      expect(schemaWriteValue('number', '7'), isA<num>());
    });

    test('unparseable text is omitted — not cleared, not sent', () {
      // Clearing a good value because someone typed a stray character would be
      // worse than doing nothing.
      expect(schemaWriteValue('integer', 'abc'), same(absentValue));
      expect(schemaWriteValue('integer', '4.5'), same(absentValue));
    });
  });

  group('times', () {
    test('seconds are dropped — the user never chose them', () {
      expect(schemaWriteValue('time', '10:00:00'), '10:00');
      expect(schemaWriteValue('time', '9:05'), '09:05');
    });

    test('an empty time clears', () {
      expect(schemaWriteValue('time', ''), isNull);
    });

    test('an impossible time is omitted rather than sent', () {
      expect(schemaWriteValue('time', '99:99'), same(absentValue));
      expect(schemaWriteValue('time', 'later'), same(absentValue));
    });
  });

  group('dates', () {
    test('kept as typed; empty clears', () {
      expect(schemaWriteValue('date', '2026-08-20'), '2026-08-20');
      expect(schemaWriteValue('datetime', '2026-08-20'), '2026-08-20');
      expect(schemaWriteValue('date', ''), isNull);
    });
  });

  group('strings', () {
    test('send their text, empty included', () {
      expect(schemaWriteValue('string', 'Prepare BOQ'), 'Prepare BOQ');
      expect(schemaWriteValue('text', '  spaced  '), 'spaced');
      // An empty string field is a cleared string, not a cleared column.
      expect(schemaWriteValue('text', ''), '');
    });
  });

  group('the omit sentinel', () {
    test('is distinct from null, which means clear', () {
      expect(absentValue, isNot(isNull));
      expect(identical(schemaWriteValue('integer', ''), absentValue), isFalse);
      expect(identical(schemaWriteValue('integer', 'abc'), absentValue), isTrue);
    });
  });
}
