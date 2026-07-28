import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Filled navy CTA (default) or ghost outline (variant). Used for sticky action
/// bars and primary form buttons.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.ghost = false,
    this.height = 52,
    this.expand = true,
    this.color,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool ghost;
  final double height;
  final bool expand;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = ghost ? AppColors.textSecondary : AppColors.white;
    final bg = ghost ? AppColors.white : (color ?? AppColors.navy);
    final child = Container(
      height: height.h,
      alignment: Alignment.center,
      padding: expand ? null : EdgeInsets.symmetric(horizontal: 22.w),
      decoration: BoxDecoration(
        color: onTap == null ? bg.withOpacity(0.5) : bg,
        borderRadius: BorderRadius.circular(14.r),
        border: ghost ? Border.all(color: AppColors.borderInput, width: 1.5) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18.sp, color: fg),
            SizedBox(width: 8.w),
          ],
          Text(label, style: AppText.custom(size: 15, weight: FontWeight.w700, color: fg)),
        ],
      ),
    );
    final tappable = GestureDetector(onTap: onTap, child: child);
    return expand ? SizedBox(width: double.infinity, child: tappable) : tappable;
  }
}

/// Sticky bottom action bar (white, top hairline) hosting one or two buttons.
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 28.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(children: children),
    );
  }
}
