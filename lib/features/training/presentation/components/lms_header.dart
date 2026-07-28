import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';

/// The white sticky top header shared by every LMS screen: a back caret, an
/// optional leading icon chip, a title, an optional trailing widget (status
/// pill / action) and an optional [bottom] block (search + filter chips) inside
/// the same white surface. Clears the 54px status-bar gap.
class LmsHeader extends StatelessWidget {
  const LmsHeader({
    super.key,
    required this.onBack,
    required this.title,
    this.leading,
    this.trailing,
    this.bottom,
    this.titleGap = 12,
    this.bottomPadding = 12,
  });

  final VoidCallback onBack;
  final Widget title;
  final Widget? leading;
  final Widget? trailing;
  final Widget? bottom;
  final double titleGap;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      padding: EdgeInsets.fromLTRB(10.w, 54.h, 16.w, bottomPadding.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: SizedBox(
                  width: 34.w,
                  height: 34.w,
                  child: Icon(PhosphorIconsBold.caretLeft, size: 22.sp, color: AppColors.textPrimary),
                ),
              ),
              if (leading != null) ...[
                SizedBox(width: 6.w),
                leading!,
                SizedBox(width: 10.w),
              ] else
                SizedBox(width: 4.w),
              Expanded(child: title),
              if (trailing != null) ...[
                SizedBox(width: 10.w),
                trailing!,
              ],
            ],
          ),
          if (bottom != null) ...[
            SizedBox(height: titleGap.h),
            bottom!,
          ],
        ],
      ),
    );
  }
}
