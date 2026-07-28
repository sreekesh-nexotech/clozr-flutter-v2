import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/entities/dash_colors.dart';

/// The dashboard's navy-fill segmented control (`segStyle9` in the prototype):
/// a grey track whose active segment is a solid navy pill with white text.
/// Distinct from the core [SegmentedControl] (white raised chip).
class DashSegmented extends StatelessWidget {
  const DashSegmented({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(2.r),
      decoration: BoxDecoration(color: DashColors.chipGrey, borderRadius: BorderRadius.circular(9.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: selectedIndex == i ? AppColors.navy : Colors.transparent,
                  borderRadius: BorderRadius.circular(7.r),
                ),
                child: Text(
                  options[i],
                  style: AppText.custom(
                    size: 12,
                    weight: FontWeight.w700,
                    color: selectedIndex == i ? AppColors.white : DashColors.textMid,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A horizontally-scrolling row of pill chips (`odChip`): active = navy fill /
/// white text, inactive = grey fill / dark text. Used for the CRM "Stuck Items"
/// selector.
class DashChipRow extends StatelessWidget {
  const DashChipRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: labels.length,
        separatorBuilder: (_, __) => SizedBox(width: 8.w),
        itemBuilder: (context, i) {
          final on = selectedIndex == i;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 13.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.navy : DashColors.chipGrey,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Text(
                labels[i],
                style: AppText.custom(
                  size: 12.5,
                  weight: on ? FontWeight.w700 : FontWeight.w600,
                  color: on ? AppColors.white : AppColors.textLabelAlt,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
