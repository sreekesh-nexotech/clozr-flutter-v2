import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';

/// The rounded LMS progress bar: a grey track with a coloured fill. Used on
/// course cards, learner rows, course detail and the player.
class LmsProgressBar extends StatelessWidget {
  const LmsProgressBar({
    super.key,
    required this.value, // 0..1
    required this.color,
    this.height = 7,
    this.track = AppColors.borderCardSoft,
  });

  final double value;
  final Color color;
  final double height;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9999.r),
      child: Container(
        height: height.h,
        color: track,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
        ),
      ),
    );
  }
}
