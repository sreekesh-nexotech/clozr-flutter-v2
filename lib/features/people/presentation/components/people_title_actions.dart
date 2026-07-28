import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// A 38×38 icon action for a People list-screen title row (search / filter),
/// with an optional blue query dot or filter-count badge. Matches the
/// prototype's header action buttons.
class PeopleIconAction extends StatelessWidget {
  const PeopleIconAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.dot = false,
    this.badge,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool dot;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38.w,
        height: 38.w,
        margin: EdgeInsets.only(left: 2.w),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 20.sp, color: AppColors.textSecondary),
            if (dot)
              Positioned(
                top: 7.h,
                right: 7.w,
                child: Container(
                  width: 7.w,
                  height: 7.w,
                  decoration: BoxDecoration(
                    color: AppColors.blueBright,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                ),
              ),
            if (badge != null)
              Positioned(
                top: 2.h,
                right: 2.w,
                child: Container(
                  constraints: BoxConstraints(minWidth: 16.w),
                  height: 16.w,
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.blueBright, borderRadius: BorderRadius.circular(8.r)),
                  child: Text(badge!, style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The navy "create" action. Icon-only (compact 38×38) by default; pass [label]
/// for the labeled pill variant (e.g. "Add role").
class PeopleCreateButton extends StatelessWidget {
  const PeopleCreateButton({super.key, required this.onTap, this.label});

  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 38.w,
          height: 38.w,
          margin: EdgeInsets.only(left: 4.w),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(10.r)),
          child: Icon(PhosphorIconsBold.plus, size: 18.sp, color: AppColors.white),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 38.h,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(10.r)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.plus, size: 13.sp, color: AppColors.white),
            SizedBox(width: 6.w),
            Text(label!, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.white)),
          ],
        ),
      ),
    );
  }
}
