import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// One saved-view definition (a boolean filter preset).
class SavedView {
  final String key;
  final String label;
  const SavedView(this.key, this.label);
}

/// Horizontal, scrollable row of saved-view filter chips (the row under the
/// status tabs on the finance list screens). Toggling a chip is fully
/// functional; a "Clear filters" chip appears once any view is active.
class SavedChipRow extends StatelessWidget {
  const SavedChipRow({
    super.key,
    required this.views,
    required this.active,
    required this.onToggle,
    required this.onClear,
    this.showClearAlways = false,
  });

  final List<SavedView> views;
  final Set<String> active;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  /// When true the "Clear filters" chip is shown even if no saved view is
  /// active (e.g. manual drawer filters are applied). Defaults to false so
  /// existing callers keep the active-only behaviour.
  final bool showClearAlways;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34.h,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (int i = 0; i < views.length; i++) ...[
              if (i > 0) SizedBox(width: 8.w),
              _chip(views[i]),
            ],
            if (active.isNotEmpty || showClearAlways) ...[
              SizedBox(width: 8.w),
              _clearChip(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(SavedView v) {
    final on = active.contains(v.key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onToggle(v.key),
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: on ? AppColors.blueSubtle : AppColors.bgChipGrey,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsFill.bookmarkSimple,
                size: 13.sp, color: on ? AppColors.blueBright : AppColors.textLabelAlt),
            SizedBox(width: 5.w),
            Text(v.label,
                style: AppText.custom(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: on ? AppColors.blueBright : AppColors.textLabelAlt)),
            if (on) ...[
              SizedBox(width: 6.w),
              Icon(PhosphorIconsBold.x, size: 11.sp, color: AppColors.blueBright),
            ],
          ],
        ),
      ),
    );
  }

  Widget _clearChip() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClear,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: AppColors.blueSubtle,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.xCircle, size: 13.sp, color: AppColors.blueBright),
            SizedBox(width: 5.w),
            Text('Clear filters',
                style: AppText.custom(
                    size: 12.5, weight: FontWeight.w700, color: AppColors.blueBright)),
          ],
        ),
      ),
    );
  }
}
