import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// LMS filter chips. [LmsFilterChip.solid] is the navy pill (course status,
/// learner role); [LmsFilterChip.subtle] is the outlined chip (learner status).
class LmsFilterChip extends StatelessWidget {
  const LmsFilterChip._({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.solid,
  });

  const LmsFilterChip.solid({
    Key? key,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) : this._(key: key, label: label, active: active, onTap: onTap, solid: true);

  const LmsFilterChip.subtle({
    Key? key,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) : this._(key: key, label: label, active: active, onTap: onTap, solid: false);

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    if (solid) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 34.h,
          padding: EdgeInsets.symmetric(horizontal: 13.w),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.navy : AppColors.bgChipGrey,
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Text(label,
              style: AppText.custom(
                  size: 12.5,
                  weight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppColors.white : AppColors.textLabelAlt)),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 30.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.tintNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(9.r),
          border: active ? null : Border.all(color: const Color(0xFFE6E7EA)),
        ),
        child: Text(label,
            style: AppText.custom(
                size: 12,
                weight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? AppColors.navy : AppColors.textMuted)),
      ),
    );
  }
}
