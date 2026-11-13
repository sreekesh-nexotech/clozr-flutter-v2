import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/crm/application/record_rows.dart';

void main() {
  test('a datetime row reads as an absolute date and time, never "Just now"',
      () {
    // A meeting that is still ahead must not collapse to a relative stamp.
    final future = DateTime.now().add(const Duration(days: 3));
    final text = recordValueText(future.toUtc().toIso8601String(), 'datetime');
    expect(text, isNot(contains('Just now')));
    expect(text, isNot(contains('ago')));
    expect(text, matches(RegExp(r'\d{2}/\d{2}/\d{4}, \d{2}:\d{2}')));
  });

  test('a blank datetime is a dash', () {
    expect(recordValueText(null, 'datetime'), '—');
  });
}
