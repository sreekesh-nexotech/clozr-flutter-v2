import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../data/mock/status_meta.dart';

/// The ubiquitous status pill: tinted background (`color` at ~9% alpha, the
/// prototype's `color + '17'`), coloured label. Radius 7, 3×8 padding, 11/700.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.fontSize = 11,
    this.hPad = 8,
    this.vPad = 3,
  });

  StatusPill.meta(StatusMeta meta, {super.key, this.fontSize = 11, this.hPad = 8, this.vPad = 3})
      : label = meta.label,
        color = meta.color;

  final String label;
  final Color color;
  final double fontSize;
  final double hPad;
  final double vPad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad.w, vertical: vPad.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(7.r),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: fontSize.sp,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// A priority tag pill using the [StatusMeta$.priorityTone] bg/fg mapping.
class PriorityPill extends StatelessWidget {
  const PriorityPill({super.key, required this.priority, this.fontSize = 11});
  final String priority;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final tone = StatusMeta$.priorityTone[priority] ?? StatusMeta$.priorityTone['low']!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(7.r)),
      child: Text(
        priority,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: fontSize.sp,
          fontWeight: FontWeight.w700,
          color: tone.fg,
        ),
      ),
    );
  }
}
