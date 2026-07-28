import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../app/config/constants.dart';
import '../../../app/theme/app_colors.dart';

/// Simulated iOS status bar + dynamic island, drawn on top of every screen so
/// the 390×844 render matches the design canvas pixel-for-pixel.
///
/// This is device chrome, not app UI — on a real device the OS draws it. It is
/// isolated here so it can be removed with a single edit if desired.
class DeviceStatusBar extends StatelessWidget {
  const DeviceStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: 52.h,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(26.w, 8.h, 26.w, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    AppConstants.statusBarClock,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w700,
                      fontSize: 15.sp,
                      color: AppColors.nearBlack,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Row(
                    children: [
                      _signalBars(),
                      SizedBox(width: 7.w),
                      Icon(Icons.wifi_rounded, size: 16.sp, color: AppColors.nearBlack),
                      SizedBox(width: 7.w),
                      _battery(),
                    ],
                  ),
                ],
              ),
            ),
            // Dynamic island.
            Positioned(
              top: 12.h,
              child: Container(
                width: 116.w,
                height: 33.h,
                decoration: BoxDecoration(
                  color: AppColors.black,
                  borderRadius: BorderRadius.circular(20.r),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signalBars() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 2.w),
          child: Container(
            width: 3.w,
            height: (5 + i * 2).h,
            decoration: BoxDecoration(
              color: AppColors.nearBlack,
              borderRadius: BorderRadius.circular(1.r),
            ),
          ),
        );
      }),
    );
  }

  Widget _battery() {
    return Row(
      children: [
        Container(
          width: 22.w,
          height: 11.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3.r),
            border: Border.all(color: AppColors.nearBlack.withOpacity(0.35), width: 1),
          ),
          padding: EdgeInsets.all(1.5.r),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.75,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.nearBlack,
                  borderRadius: BorderRadius.circular(1.5.r),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 1.w),
        Container(
          width: 1.5.w,
          height: 4.h,
          decoration: BoxDecoration(
            color: AppColors.nearBlack.withOpacity(0.4),
            borderRadius: BorderRadius.circular(1.r),
          ),
        ),
      ],
    );
  }
}
