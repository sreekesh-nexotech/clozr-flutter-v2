import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Centered empty-state block: rounded icon chip, title, muted body, optional
/// CTA. Matches the prototype's list empty states.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.iconColor = AppColors.textPlaceholder,
    this.iconBg = AppColors.borderCardSoft,
    this.ctaLabel,
    this.ctaIcon,
    this.onCta,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color iconColor;
  final Color iconBg;
  final String? ctaLabel;
  final IconData? ctaIcon;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 56.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66.r,
            height: 66.r,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(19.r)),
            child: Icon(icon, size: 30.sp, color: iconColor),
          ),
          SizedBox(height: 16.h),
          Text(title, style: AppText.sectionTitle(), textAlign: TextAlign.center),
          SizedBox(height: 6.h),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 240.w),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.textMuted).copyWith(height: 1.5),
            ),
          ),
          if (ctaLabel != null) ...[
            SizedBox(height: 18.h),
            GestureDetector(
              onTap: onCta,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ctaIcon != null) ...[
                      Icon(ctaIcon, size: 15.sp, color: AppColors.white),
                      SizedBox(width: 8.w),
                    ],
                    Text(ctaLabel!, style: AppText.bodyStrong(color: AppColors.white)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
