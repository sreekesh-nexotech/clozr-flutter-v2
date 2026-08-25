// Every date picker in the app opened on 9 July 2026 — the prototype's frozen
// clock — so scheduling anything meant scrolling back to today first.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';

void main() {
  tearDown(() => filterNow = defaultFilterNow);

  group('the pickers open on today', () {
    test('kFilterToday follows the clock', () {
      filterNow = () => DateTime(2026, 8, 18, 14, 30);
      expect(kFilterToday, DateTime(2026, 8, 18));
    });

    test('it is a date, not an instant — a picker seeds off midnight', () {
      filterNow = () => DateTime(2026, 8, 18, 23, 59, 59);
      final t = kFilterToday;
      expect([t.hour, t.minute, t.second], [0, 0, 0]);
    });

    test('it moves with the day rather than pinning to the seed date', () {
      filterNow = () => DateTime(2027, 1, 1);
      expect(kFilterToday, DateTime(2027, 1, 1));
      expect(kFilterToday, isNot(kMockFilterToday));
    });

    test('mock mode keeps the frozen clock the seed is built around', () {
      // The bundled records are dated relative to it; a real "today" would put
      // every one of them out of range.
      expect(kMockFilterToday, DateTime(2026, 7, 9));
    });
  });
}
