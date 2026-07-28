import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../data/mock/status_meta.dart';

/// Feature-local LMS styling lookups. These are the design's LMS-only tokens
/// (progress-bar colours, role-pill bg/fg pairs) that don't exist in the shared
/// [AppColors] palette. Centralised here so no widget hardcodes a hex — the
/// module contract forbids editing the core theme, so this is the LMS single
/// source of truth for them.
class LmsStyle {
  LmsStyle._();

  /// Neutral grey used for "not started" progress fills (`#C2C6CD`).
  static const Color barNotStarted = Color(0xFFC2C6CD);

  /// Progress-bar fill colour for an LMS status key (mirrors `lmsBarColor`).
  static Color barColor(String status) {
    switch (status) {
      case 'inprogress':
        return AppColors.warning;
      case 'completed':
        return AppColors.success;
      case 'overdue':
        return AppColors.error;
      case 'notstarted':
      default:
        return barNotStarted;
    }
  }

  /// Role-pill background + foreground (mirrors `LMS_ROLEPILL`).
  static ({Color bg, Color fg}) rolePill(String role) {
    switch (role) {
      case 'System Admin':
        return (bg: AppColors.tintNavy, fg: AppColors.navy);
      case 'Manager':
        return (bg: AppColors.blueSubtle, fg: AppColors.blueBright);
      case 'Sales rep':
        return (bg: AppColors.tintGreen, fg: AppColors.success);
      case 'Project associate':
        return (bg: const Color(0xFFEEF0FB), fg: const Color(0xFF4A5BC4));
      case 'Viewer':
      default:
        return (bg: AppColors.bgChipGrey, fg: AppColors.textMuted2);
    }
  }

  /// The status pill meta for the published/draft badge on course cards.
  static StatusMeta publishMeta(bool published) => published
      ? const StatusMeta('Published', AppColors.success)
      : const StatusMeta('Draft', AppColors.textMuted);
}
