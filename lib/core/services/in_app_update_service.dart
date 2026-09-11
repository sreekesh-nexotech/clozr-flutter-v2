import 'dart:async';
import 'dart:io';

import 'package:in_app_update/in_app_update.dart';

import '../monitoring/app_monitoring.dart';

/// Prompts a Play Store update when one is available (Play Core's in-app
/// update API), so a fix or a feature reaches installed devices without
/// everyone having to remember to visit the Store.
///
/// Android-only — there is no iOS equivalent, and the plugin itself throws a
/// `MissingPluginException` off-Android, so [Platform.isAndroid] guards every
/// call rather than trusting the plugin to no-op quietly. Silent on every
/// other outcome too (no Play Store install, nothing newer published, a check
/// that throws): update-nagging is never worth interrupting a screen for.
class InAppUpdateService {
  InAppUpdateService._();

  static Future<void> checkAndPrompt() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;

      // Immediate hands the whole screen to Play until the user updates or
      // backs out — the right default while the app has no install base yet
      // to protect from that disruption. Flexible (background download,
      // installed on the next call once it finishes) is the fallback for the
      // rarer update Play itself marks ineligible for the immediate flow.
      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) {
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } on Object catch (error, stack) {
      // Never worth surfacing to the user — but worth knowing if the check
      // itself starts failing across a fleet.
      unawaited(AppMonitoring.captureError(error, stack, message: 'InAppUpdate check failed'));
    }
  }
}
