import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../app/theme/app_colors.dart';

/// Initials avatar. Defaults to a circle; pass [radius] for a rounded-square
/// (e.g. the 62×62 / r15 lead-detail avatar).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.initials,
    this.size = 30,
    this.background = AppColors.navy,
    this.foreground = AppColors.white,
    this.fontSize,
    this.radius,
    this.border,
  });

  final String initials;
  final double size;
  final Color background;
  final Color foreground;
  final double? fontSize;
  final double? radius; // null => circle
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.w,
      height: size.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius == null ? null : BorderRadius.circular(radius!.r),
        border: border,
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: (fontSize ?? (size > 26 ? 11 : 10)).sp,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// Overlapping avatar stack (`marginLeft: -8` in the prototype), each with a
/// 2px white ring.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.items,
    this.size = 30,
    this.overlap = 8,
  });

  /// (initials, colour) pairs.
  final List<(String, Color)> items;
  final double size;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size.w,
      child: Stack(
        children: [
          for (int i = 0; i < items.length; i++)
            Positioned(
              left: i * (size - overlap).w,
              child: InitialsAvatar(
                initials: items[i].$1,
                size: size,
                background: items[i].$2,
                border: Border.all(color: AppColors.white, width: 2),
              ),
            ),
        ],
      ),
    ).withStackWidth(items.length, size, overlap);
  }
}

extension on Widget {
  /// Constrain the stack's width so trailing content sits flush.
  Widget withStackWidth(int count, double size, double overlap) {
    if (count == 0) return SizedBox(width: 0, height: size.w);
    final width = (size + (count - 1) * (size - overlap)).w;
    return SizedBox(width: width, child: this);
  }
}
