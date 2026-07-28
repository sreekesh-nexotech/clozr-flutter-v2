import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// A single option in a [ModeToggle].
class ModeOption {
  final IconData icon;
  final String label;
  const ModeOption(this.icon, this.label);
}

/// The two-segment mode switcher used above the status tabs on Payments
/// (Payments | Invoices) and Products (Products | Packages). Grey track with a
/// raised white active chip, icon + label per segment.
class ModeToggle extends StatelessWidget {
  const ModeToggle({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<ModeOption> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(4.r),
      decoration: BoxDecoration(
        color: AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(13.r),
      ),
      child: Row(
        children: [
          for (int i = 0; i < options.length; i++) ...[
            if (i > 0) SizedBox(width: 6.w),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Container(
                  height: 42.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selectedIndex == i ? AppColors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11.r),
                    border: selectedIndex == i
                        ? Border.all(color: const Color(0xFFE6E7EA))
                        : null,
                    boxShadow: selectedIndex == i
                        ? [
                            BoxShadow(
                              color: const Color(0xFF101828).withOpacity(0.10),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(options[i].icon,
                          size: 16.sp,
                          color: selectedIndex == i ? AppColors.navy : AppColors.textMuted2),
                      SizedBox(width: 7.w),
                      Text(
                        options[i].label,
                        style: AppText.custom(
                          size: 13.5,
                          weight: selectedIndex == i ? FontWeight.w700 : FontWeight.w500,
                          color: selectedIndex == i ? AppColors.navy : AppColors.textMuted2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
