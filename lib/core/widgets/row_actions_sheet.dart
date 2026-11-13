import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import 'app_bottom_sheet.dart';

/// One row action in [showRowActionsSheet].
class RowAction {
  const RowAction(this.id, this.icon, this.label);
  final String id;
  final IconData icon;
  final String label;

  static RowAction view(String noun) =>
      RowAction('view', PhosphorIconsRegular.eye, 'View $noun');
  static RowAction edit(String noun) =>
      RowAction('edit', PhosphorIconsRegular.pencilSimple, 'Edit $noun');
}

/// The list row actions every list offers on a long press — View, then Edit
/// where the record can be edited on mobile (UI/UX audit #52: one row-action
/// set across lists). Returns the picked [RowAction.id], or null.
Future<String?> showRowActionsSheet(
  BuildContext context, {
  required String title,
  required List<RowAction> actions,
}) =>
    showClozrSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: title),
          for (final a in actions)
            ListTile(
              leading:
                  Icon(a.icon, size: 20.sp, color: AppColors.textSecondary),
              title: Text(a.label, style: AppText.bodyStrong()),
              onTap: () => Navigator.of(ctx).pop(a.id),
            ),
          SizedBox(height: 12.h),
        ],
      ),
    );
