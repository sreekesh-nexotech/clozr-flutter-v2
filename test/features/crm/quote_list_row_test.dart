import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/core/utils/inr_format.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/quotes_remote_ds.dart';

void main() {
  test('formatInrFull groups the Indian way and drops empty paise', () {
    expect(formatInrFull(301785.69), '₹3,01,785.69');
    expect(formatInrFull(1000), '₹1,000');
    expect(formatInrFull(null), '—');
  });

  test('a list row keeps exact totals and activity, and no line count', () {
    final q = quoteFromApi({
      'quotation_id': 'u1',
      'quotation_number': 'QTN-1',
      'status': {'name': 'Draft'},
      'total_amount': '1000.00',
      'grand_total': '1180.00',
      'updated_at': '2026-10-31T10:00:00+05:30',
      'created_at': '2026-10-30T10:00:00+05:30',
    })!;
    expect(q.subTotalExact, 1000);
    expect(q.grandTotalExact, 1180);
    expect(q.updatedAt, isNotNull);
    expect(q.createdAt, isNotNull);
    expect(q.items, isEmpty);
  });
}
