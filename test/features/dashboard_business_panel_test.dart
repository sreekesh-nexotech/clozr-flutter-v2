import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/utils/inr_format.dart';
import 'package:clozrapp/features/dashboard/application/providers/dashboard_providers.dart';
import 'package:clozrapp/features/dashboard/domain/entities/dashboard_models.dart';
import 'package:clozrapp/features/dashboard/infrastructure/data_sources/remote/dashboard_remote_ds.dart';
import 'package:clozrapp/features/dashboard/presentation/components/panels/business_panel.dart';

/// Business tab edge cases: an empty org, very large / very small figures and
/// long customer names must render without overflow.
void main() {
  Future<void> pumpPanel(WidgetTester tester, DashboardData data,
      {Size size = const Size(390, 844), double textScale = 1}) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [dashboardDataProvider.overrideWithValue(data)],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: const Scaffold(
              body: SingleChildScrollView(child: BusinessPanel())),
        ),
      ),
    ));
    await tester.pump();
  }

  DashboardData mapped(Map<String, Object?> raw) =>
      DashboardRemoteDataSource.mapDashboard(raw, DashboardData.empty());

  test('amounts from a thousand crore keep Indian grouping', () {
    expect(formatInr(1200000000000), '₹1,20,000Cr');
    expect(formatInr(12345678900), '₹1,235Cr');
    expect(formatInr(9990000000), '₹999Cr');
    expect(formatInr(850), '₹850');
    expect(formatInr(100000), '₹1L');
    expect(formatInr(-1200000000000), '-₹1,20,000Cr');
  });

  testWidgets('an empty org shows zeros and honest empty states',
      (tester) async {
    await pumpPanel(tester, DashboardData.empty());
    expect(tester.takeException(), isNull);
    expect(find.text('No outstanding dues'), findsOneWidget);
    expect(find.text('No customer activity'), findsOneWidget);
    expect(find.text('Sales pipeline'), findsOneWidget);
    expect(find.text('NaN'), findsNothing);
  });

  testWidgets(
      'a ₹1.2 lakh crore pipeline fits its card and a ₹850 figure shows in full',
      (tester) async {
    final d = mapped({
      DashboardRemoteDataSource.kCustomerKpis: {
        'sales_pipeline': {'amount': '1200000000000.00', 'trend_pct': 5.0},
        'payments_collected': {
          'collected': '850.00',
          'expected': '99999999999.00'
        },
        'overdue_receivables': {'amount': '0.00', 'customer_count': 0},
        'open_tickets': {'count': 0},
      },
    });
    await pumpPanel(tester, d, size: const Size(320, 700), textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('₹1,20,000'), findsOneWidget);
    expect(find.text('₹850'), findsOneWidget);
  });

  testWidgets('long names and many rows do not overflow, even at 1.3× text',
      (tester) async {
    final longName =
        'Bharat Heavy Electricals And Allied Industries Private Limited Chennai';
    final d = mapped({
      DashboardRemoteDataSource.kTopCustomers: {
        'top_outstanding': [
          for (var i = 0; i < 8; i++)
            {
              'customer_id': 'c$i',
              'name': '$longName $i',
              'outstanding_amount': '${(i + 1) * 12345}.00',
              'oldest_overdue_days': 10 + i,
            }
        ],
        'top_by_value': [
          for (var i = 0; i < 8; i++)
            {
              'customer_id': 'v$i',
              'name': '$longName $i',
              'total_value': '${(i + 1) * 250000}.00',
              'outstanding_amount': '0.00',
            }
        ],
      },
    });
    await pumpPanel(tester, d, size: const Size(320, 700), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
