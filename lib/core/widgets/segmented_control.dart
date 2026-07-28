import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Compact pill segmented control (e.g. Priority|Due, ₹Value|Days). The active
/// segment gets a white raised chip inside a grey track.
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 30,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height.h,
      padding: EdgeInsets.all(3.r),
      decoration: BoxDecoration(
        color: AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(9.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selectedIndex == i ? AppColors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(7.r),
                  boxShadow: selectedIndex == i
                      ? [
                          BoxShadow(
                            color: const Color(0xFF101828).withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  options[i],
                  style: AppText.custom(
                    size: 12,
                    weight: FontWeight.w700,
                    color: selectedIndex == i ? AppColors.navy : AppColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
