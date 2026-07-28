import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../app/theme/app_colors.dart';

/// One status/filter tab chip. Active: blue-subtle fill, 1.5px #A6D1FF ring,
/// navy label. Inactive: white, 1px #E6E7EA ring, muted label. Optional status
/// dot (Customers screen).
class TabChip extends StatelessWidget {
  const TabChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 40.h,
        padding: EdgeInsets.only(left: dotColor != null ? 13.w : 17.w, right: dotColor != null ? 15.w : 17.w),
        decoration: BoxDecoration(
          color: active ? AppColors.blueSubtle : AppColors.white,
          borderRadius: BorderRadius.circular(13.r),
          border: Border.all(
            color: active ? const Color(0xFFA6D1FF) : const Color(0xFFE6E7EA),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 9.w,
                height: 9.w,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              SizedBox(width: 7.w),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13.5.sp,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.navy : AppColors.textLabelAlt,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal, scrollable row of [TabChip]s.
class TabChipRow extends StatelessWidget {
  const TabChipRow({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: 9.w),
            children[i],
          ],
        ],
      ),
    );
  }
}
