import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/routes.dart';

/// Shared back behaviour for LMS screens: pop if possible, otherwise fall back
/// to [fallback] — the Training Dashboard for the admin screens, My Trainings
/// for the learner ones (a learner cannot open the dashboard).
void lmsBack(BuildContext context, {String fallback = Routes.lmsOverview}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
