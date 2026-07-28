import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../domain/entities/course.dart';

/// A course thumbnail: a tinted rounded box with the course's centred glyph.
/// Sizes/opacities vary by surface (card 54, banner 128, grid, player), so they
/// are parameterised.
class LmsThumb extends StatelessWidget {
  const LmsThumb({
    super.key,
    required this.course,
    this.width,
    this.height = 54,
    this.iconSize = 24,
    this.radius = 13,
    this.iconOpacity = 1,
    this.child,
  });

  final Course course;
  final double? width;
  final double height;
  final double iconSize;
  final double radius;
  final double iconOpacity;

  /// Optional overlay (e.g. a status pill positioned inside the thumb).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width?.w,
      height: height.h,
      decoration: BoxDecoration(
        color: course.tint,
        borderRadius: BorderRadius.circular(radius.r),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(course.icon, size: iconSize.sp, color: course.accent.withOpacity(iconOpacity)),
          if (child != null) child!,
        ],
      ),
    );
  }
}
