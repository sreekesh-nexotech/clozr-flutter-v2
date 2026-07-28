import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';

/// A titled white dashboard card. Optional [subtitle] under the title and an
/// optional [trailing] widget (a segmented control or a static badge). The
/// prototype's section cards use the elevated ClozrCard chrome.
class DashSectionCard extends StatelessWidget {
  const DashSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClozrCard(
      padding: padding ?? EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (subtitle != null) ...[
                      SizedBox(height: 1.h),
                      Text(subtitle!, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[SizedBox(width: 10.w), trailing!],
            ],
          ),
          child,
        ],
      ),
    );
  }
}

/// A "View more / View all …" footer link (blue) used at the bottom of list
/// cards in the manager panels.
class DashViewMore extends StatelessWidget {
  const DashViewMore({super.key, required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 13.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.blueBright)),
            SizedBox(width: 6.w),
            Icon(icon, size: 12.sp, color: AppColors.blueBright),
          ],
        ),
      ),
    );
  }
}

/// A row with the prototype's `inset 0 -1px 0 #F3F4F5` bottom hairline.
class DashHairlineRow extends StatelessWidget {
  const DashHairlineRow({super.key, required this.child, this.onTap, this.padding});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: padding ?? EdgeInsets.symmetric(vertical: 12.h),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.bgLight, width: 1)),
      ),
      child: child,
    );
    if (onTap == null) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}
