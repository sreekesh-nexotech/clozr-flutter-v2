import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/app/router/routes.dart';
import 'package:clozrapp/features/shell/presentation/clozr_bottom_nav.dart';

/// The nav stacks several [BackdropFilter]s to ramp the strip's top edge, and
/// decorates a rounded pill over them. Both are the kind of thing that fails
/// only at paint time — a [BoxDecoration] throws if a borderRadius meets sides
/// of differing colour, for instance — which `analyze` never sees.
void main() {
  testWidgets('bottom nav pill paints without a border assertion', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ClozrBottomNav(location: Routes.home),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(BackdropFilter), findsWidgets);
  });
}
