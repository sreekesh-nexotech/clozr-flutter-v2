// Smoke test — verifies the app boots inside the shell.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clozrapp/app/app.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The default Ahem test font renders every glyph as a full-size square,
    // which overflows the dense 390px layout. Load the real Manrope font so
    // text metrics match the app.
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope-VariableFont_wght.ttf'));
    await loader.load();
  });

  testWidgets('App boots into the shell', (WidgetTester tester) async {
    // The layout is built against the 390×844 design canvas; the default
    // 800×600@3x test viewport (267 logical px wide) overflows everything.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: ClozrApp()));
    await tester.pump();
    expect(find.byType(ClozrApp), findsOneWidget);
  });
}
