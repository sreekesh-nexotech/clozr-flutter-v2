import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/widgets/list_skeleton.dart';

/// The skeleton is rendered both as a whole screen's loading state and *inside*
/// scrolling bodies (a lead's activity tab shows it while the tab's provider
/// resolves). The embedded case hands it unbounded height, which a viewport
/// that does not shrink-wrap cannot survive: it throws during resize, never
/// gets a size, and the next line of its own layout trips `hasSize`. That
/// crashed the lead detail screen on every slow load.
void main() {
  Widget host(Widget child) => ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('lays out inside an unbounded-height parent', (tester) async {
    await tester.pumpWidget(host(
      ListView(children: const [ListSkeleton(itemCount: 3)]),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SkeletonBox), findsNWidgets(3));

    // Disposes the shimmer's ticker before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('still lays out as a full-height list', (tester) async {
    await tester.pumpWidget(host(const ListSkeleton(itemCount: 4)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SkeletonBox), findsNWidgets(4));

    await tester.pumpWidget(const SizedBox());
  });
}
