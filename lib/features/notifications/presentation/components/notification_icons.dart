import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/app_notification.dart';

/// Per-category icon/colour combos, copied from the mock seed so remote rows
/// look identical to the design.
///
/// Lives in the presentation layer: it is the only reason the notifications
/// mapper used to import an icon package, which made every test that touched
/// the mapper fail to compile.
({IconData icon, Color color, Color bg}) notificationIconFor(
  String category, {
  bool urgent = false,
  String type = '',
}) {
  switch (category) {
    case 'leads':
      return (
        icon: PhosphorIconsFill.userPlus,
        color: AppColors.blueBright,
        bg: AppColors.tintBlue,
      );
    case 'payments':
      return urgent
          ? (icon: PhosphorIconsFill.warningCircle, color: AppColors.error, bg: AppColors.tintRed)
          : (icon: PhosphorIconsFill.currencyInr, color: AppColors.success, bg: AppColors.tintGreen);
    case 'tasks':
      return urgent
          ? (icon: PhosphorIconsFill.warning, color: AppColors.warningDeep, bg: AppColors.tintAmber)
          : (icon: PhosphorIconsFill.listChecks, color: AppColors.blueBright, bg: AppColors.tintBlue);
    case 'ops':
      return urgent
          ? (icon: PhosphorIconsFill.kanban, color: AppColors.error, bg: AppColors.tintRed)
          : (icon: PhosphorIconsFill.briefcase, color: AppColors.blueBright, bg: AppColors.tintBlue);
    case 'help':
      return urgent
          ? (icon: PhosphorIconsFill.ticket, color: AppColors.error, bg: AppColors.tintRed)
          : (icon: PhosphorIconsFill.chatCircleDots, color: AppColors.blueBright, bg: AppColors.tintBlue);
    case 'training':
      return (
        icon: PhosphorIconsFill.graduationCap,
        color: AppColors.blueBright,
        bg: AppColors.tintBlue,
      );
    default: // system
      if (type.toLowerCase().contains('user')) {
        return (icon: PhosphorIconsFill.userCirclePlus, color: AppColors.textLabelAlt, bg: AppColors.tintGrey);
      }
      return urgent
          ? (icon: PhosphorIconsFill.plug, color: AppColors.pending, bg: AppColors.tintPurple)
          : (icon: PhosphorIconsFill.downloadSimple, color: AppColors.textLabelAlt, bg: AppColors.tintGrey);
  }
}

/// The look for a row: whatever the seed supplied, else resolved from the
/// row's own category, urgency and type.
({IconData icon, Color color, Color bg}) notificationLook(AppNotification n) {
  final icon = n.icon;
  final color = n.iconColor;
  final bg = n.iconBg;
  if (icon != null && color != null && bg != null) {
    return (icon: icon, color: color, bg: bg);
  }
  return notificationIconFor(n.category, urgent: n.urgent, type: n.type);
}
