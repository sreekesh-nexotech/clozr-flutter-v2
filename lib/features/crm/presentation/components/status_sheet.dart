import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../data/mock/status_meta.dart';

/// A selectable status option: its status key plus display meta.
class StatusOption {
  final String key;
  final StatusMeta meta;
  const StatusOption(this.key, this.meta);
}

/// Presents the Clozr status-change sheet: a titled list of coloured-dot options
/// with a check on the current one. Returns the chosen key (or null if
/// dismissed). Used by the finance detail status pills.
Future<String?> showStatusSheet({
  required BuildContext context,
  required String title,
  required List<StatusOption> options,
  required String currentKey,
}) {
  return showClozrSheet<String>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: title),
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(o.key),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 13.h),
                    decoration: BoxDecoration(
                      color: o.key == currentKey ? const Color(0xFFF6F8FB) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 11.w,
                          height: 11.w,
                          decoration: BoxDecoration(color: o.meta.color, shape: BoxShape.circle),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(o.meta.label,
                              style: AppText.custom(size: 14.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
                        ),
                        if (o.key == currentKey)
                          Icon(PhosphorIconsBold.check, size: 18.sp, color: AppColors.success),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
