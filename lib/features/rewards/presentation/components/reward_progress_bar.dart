import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';

/// The thin rounded progress bar used on goal cards and the Closer Track.
class RewardProgressBar extends StatelessWidget {
  const RewardProgressBar({
    super.key,
    required this.pct,
    this.track = AppColors.borderCardSoft,
    this.fill = AppColors.success,
  });

  final int pct; // 0–100
  final Color track;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 7.h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (pct.clamp(0, 100)) / 100,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
        ),
      ),
    );
  }
}

/// The uppercase "TO ACHIEVE" / "YOU'LL GET" overline (icon + tracked caps).
class RewardOverline extends StatelessWidget {
  const RewardOverline({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13.sp, color: AppColors.textPlaceholder),
        SizedBox(width: 6.w),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10.5.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPlaceholder,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }
}
