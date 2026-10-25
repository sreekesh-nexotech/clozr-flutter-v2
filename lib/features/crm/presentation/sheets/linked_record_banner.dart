import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// "Linked to <record>" — the webapp `AddTaskModal` banner shown when a task or
/// follow-up is raised from a record's tab (a customer's), so the user can see
/// what the new record will be attached to.
class LinkedRecordBanner extends StatelessWidget {
  const LinkedRecordBanner({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
      decoration: BoxDecoration(
        color: AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(11.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.link, size: 15.sp, color: AppColors.textMuted),
          SizedBox(width: 8.w),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Linked to '),
                TextSpan(
                  text: label,
                  style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
