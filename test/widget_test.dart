// Smoke test — verifies the app boots inside the shell.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clozrapp/app/app.dart';

void main() {
  testWidgets('App boots into the shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ClozrApp()));
    await tester.pump();
    expect(find.byType(ClozrApp), findsOneWidget);
  });
}
