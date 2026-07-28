import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/routes.dart';

/// Shared back behaviour for LMS screens: pop if possible, otherwise fall back
/// to the Training Overview (the module's home), or to the Dashboard when
/// Overview *is* the current screen.
///
/// The drawer navigates with `context.go`, which clears the stack — so entering
/// Training from the drawer leaves nothing to pop. Without the Overview check
/// the fallback sent Overview to itself, which is a no-op: with no drawer
/// button and no bottom nav on LMS routes, that left the user stuck.
void lmsBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  final isOverview = GoRouterState.of(context).uri.path == Routes.lmsOverview;
  context.go(isOverview ? Routes.dashboard : Routes.lmsOverview);
}
