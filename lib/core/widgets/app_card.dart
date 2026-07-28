import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../app/theme/app_colors.dart';

/// The standard white card: 16px radius, inset 1px border, soft shadow. The
/// prototype uses two shadow treatments — a flat inset-only card and an
/// elevated card with a layered drop shadow. Toggle via [elevated].
class ClozrCard extends StatelessWidget {
  const ClozrCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 16,
    this.elevated = true,
    this.onTap,
    this.borderColor = AppColors.borderCardSoft,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool elevated;
  final VoidCallback? onTap;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding ?? EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(radius.r),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: const Color(0xFF101828).withOpacity(0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
                BoxShadow(
                  color: const Color(0xFF101828).withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card);
  }
}

/// A thin 1px divider matching the prototype's `#EEF0F3` hairlines.
class ClozrDivider extends StatelessWidget {
  const ClozrDivider({super.key, this.height = 1, this.color = AppColors.borderCardSoft, this.margin});
  final double height;
  final Color color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(margin: margin, height: height.h, color: color);
  }
}
