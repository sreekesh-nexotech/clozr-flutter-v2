import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/dashboard/domain/entities/dashboard_models.dart';
import 'package:clozrapp/features/dashboard/presentation/components/dash_bars.dart';

/// Lead Funnel edge cases: all-zero, single stage, very large counts, long stage names.
void main() {
  Future<void> pump(WidgetTester t, List<DashBar> bars,
      {String? emptyTitle, double w = 320}) async {
    t.view.physicalSize = Size(w * 2, 1400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: DashBars(
              bars: bars,
              chartHeight: 138,
              gradient: true,
              dimLast: true,
              emptyTitle: emptyTitle,
              emptyHint: 'hint'),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('an all-zero funnel reads as an empty state', (t) async {
    await pump(t, [const DashBar('New', 0), const DashBar('Won', 0)],
        emptyTitle: 'No leads in this period');
    expect(find.text('No leads in this period'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('one populated stage still draws the chart', (t) async {
    await pump(t, [const DashBar('New', 12), const DashBar('Won', 0)],
        emptyTitle: 'No leads in this period');
    expect(find.text('No leads in this period'), findsNothing);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('big counts compact and long names stay on one line', (t) async {
    await pump(t, [
      const DashBar('Negotiation', 123456),
      const DashBar('Contacted', 9999),
      const DashBar('Qualified', 12000),
      const DashBar('Proposal', 2500000),
      const DashBar('Verification Pending', 7),
      const DashBar('RT-ST03 lead notype', 1),
      const DashBar('MOF', 3),
      const DashBar('BOF', 4),
    ]);
    expect(t.takeException(), isNull);
    expect(find.text('123.5K'), findsOneWidget);
    expect(find.text('9999'), findsOneWidget);
    expect(find.text('12K'), findsOneWidget);
    expect(find.text('2.5M'), findsOneWidget);
    expect(find.text('Negotiation'), findsOneWidget);
  });
}
