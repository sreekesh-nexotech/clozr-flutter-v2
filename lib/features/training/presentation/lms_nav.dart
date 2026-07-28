import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/routes.dart';

/// Shared back behaviour for LMS screens: pop if possible, otherwise fall back
/// to the Training Overview (the module's home).
void lmsBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.lmsOverview);
  }
}
