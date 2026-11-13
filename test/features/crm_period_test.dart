import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/crm/application/providers/crm_home_providers.dart';

void main() {
  test('this month is the server default and sends nothing', () {
    expect(CrmPeriod.thisMonth.query(null), isEmpty);
  });

  test('presets send their API period', () {
    expect(CrmPeriod.lastMonth.query(null), {'period': 'last_month'});
    expect(CrmPeriod.ytd.query(null), {'period': 'ytd'});
    expect(CrmPeriod.last90.query(null), {'period': 'last_90_days'});
  });

  test('a custom range sends inclusive from / to', () {
    final r = DateTimeRange(
        start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31));
    expect(CrmPeriod.custom.query(r),
        {'period': 'custom', 'from': '2026-10-01', 'to': '2026-10-31'});
    expect(CrmPeriod.custom.query(null), isEmpty);
  });
}
