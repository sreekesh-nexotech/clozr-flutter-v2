import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// Shared building blocks for the CRM add sheets (Add customer / follow-up /
/// task). Keeps the three focused-but-faithful forms consistent with the
/// prototype's sheet chrome.

/// Two-letter initials from a name (first letters of the first two words).
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// A short, session-unique id with the given [prefix] (e.g. `C`, `TL-`, `F`).
String genId(String prefix) =>
    '$prefix${DateTime.now().millisecondsSinceEpoch.remainder(100000)}';

/// A field label (matches the add-sheet label style in the prototype).
class SheetFieldLabel extends StatelessWidget {
  const SheetFieldLabel(this.label, {super.key, this.required = false});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 7.h),
      child: Row(
        children: [
          Text(label,
              style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
          if (required)
            Text(' *',
                style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
        ],
      ),
    );
  }
}

/// A selectable pill used for status / type / priority choices in the sheets.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dot,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: selected ? AppColors.blueSubtle : AppColors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: selected ? const Color(0xFFA6D1FF) : const Color(0xFFE6E7EA),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              SizedBox(width: 7.w),
            ] else if (icon != null) ...[
              Icon(icon, size: 14.sp, color: selected ? AppColors.navy : AppColors.textLabelAlt),
              SizedBox(width: 6.w),
            ],
            Text(label,
                style: AppText.custom(
                  size: 13,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.navy : AppColors.textLabelAlt,
                )),
          ],
        ),
      ),
    );
  }
}

/// The sticky primary action button in the sheet footer.
class SheetSubmitBar extends StatelessWidget {
  const SheetSubmitBar({super.key, required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 24.h),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15.sp, color: AppColors.white),
              SizedBox(width: 8.w),
              Text(label, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
