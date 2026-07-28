import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// The white sticky footer used by LMS screens (top hairline, generous bottom
/// padding for the home indicator). Hosts one or more action buttons.
class LmsFooter extends StatelessWidget {
  const LmsFooter({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 26.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: child,
    );
  }
}

/// The filled navy CTA used across LMS footers (height 50, radius 14, soft
/// navy drop shadow). Optional leading icon.
class LmsCtaButton extends StatelessWidget {
  const LmsCtaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.flex = 1,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16.sp, color: AppColors.white),
              SizedBox(width: 8.w),
            ],
            Text(label, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
          ],
        ),
      ),
    );
  }
}

/// The ghost/outline button used alongside [LmsCtaButton] in two-button footers.
class LmsGhostButton extends StatelessWidget {
  const LmsGhostButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: const Color(0xFFE6E7EA), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16.sp, color: AppColors.textSecondary),
              SizedBox(width: 7.w),
            ],
            Text(label, style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
