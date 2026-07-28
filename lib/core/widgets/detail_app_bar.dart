import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Back-header for detail / form screens: caret-left back control, a
/// "Section / name" title, and an optional trailing action (overflow menu or a
/// text button). Layout matches the prototype's `54px 16px 12px` header.
class DetailAppBar extends StatelessWidget {
  const DetailAppBar({
    super.key,
    required this.section,
    this.name,
    this.onBack,
    this.trailing,
  });

  /// Bold segment, e.g. "Lead".
  final String section;

  /// Muted `/ name` segment, e.g. "Ramesh Pillai". Omit for form screens.
  final String? name;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 12.h),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack ?? () => _defaultBack(context),
            child: Padding(
              padding: EdgeInsets.only(right: 12.w),
              child: Icon(PhosphorIconsBold.caretLeft, size: 22.sp, color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: name == null ? section : '$section ',
                style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3),
                children: name == null
                    ? null
                    : [
                        TextSpan(
                          text: '/ $name',
                          style: AppText.custom(size: 16, weight: FontWeight.w600, color: AppColors.textPlaceholder),
                        ),
                      ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }

  static void _defaultBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }
}

/// A 34×34 tappable overflow / icon button for the [DetailAppBar] trailing slot.
class DetailIconAction extends StatelessWidget {
  const DetailIconAction({super.key, required this.icon, required this.onTap, this.color = AppColors.textSecondary});
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 34.w,
        height: 34.w,
        child: Icon(icon, size: 21.sp, color: color),
      ),
    );
  }
}
