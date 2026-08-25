import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../app/theme/app_colors.dart';

/// Presents a Clozr-style bottom sheet: rounded 24px top corners, a grabber
/// handle, `#FDFDFD` background, capped at 84% height, over a 0.42 scrim.
/// Matches the prototype's sheet chrome.
Future<T?> showClozrSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    // Present on the root navigator so the sheet (and its scrim) sits ABOVE the
    // shell's bottom nav — otherwise the nav overlaps the sticky footer / Apply
    // CTA on nav-bearing screens like the dashboards and list filters (#6).
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (ctx) => ClozrSheetContainer(child: builder(ctx)),
  );
}

/// The sheet's visual container (grabber + rounded surface). Use directly if
/// you need a sheet inside a custom presentation.
class ClozrSheetContainer extends StatelessWidget {
  const ClozrSheetContainer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // Lift the sheet above the keyboard AND shrink its cap by the same amount,
    // otherwise an 84%-tall sheet pushed up by the inset overflows the top.
    // Without this the keyboard simply draws over the sheet's sticky footer —
    // e.g. the filter drawer's "Name this view…" field.
    final maxHeight = math.max(
      0.0,
      math.min(844.h * 0.84, media.size.height - media.padding.top - keyboard - 24.h),
    );
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: AppColors.bgApp,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 10.h, bottom: 4.h),
              child: Container(
                width: 38.w,
                height: 5.h,
                decoration: BoxDecoration(
                  color: AppColors.borderGrey,
                  borderRadius: BorderRadius.circular(3.r),
                ),
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// A standard sheet header: title on the left, close (×) button on the right.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.onClose});
  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18.w, 8.h, 14.w, 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Expanded, not bare: titles are often a record name (the action menu
          // is headed by the project/customer itself), and an unconstrained one
          // pushed the close button off the row.
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                )),
          ),
          SizedBox(width: 10.w),
          GestureDetector(
            onTap: onClose ?? () => Navigator.of(context).maybePop(),
            child: Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(9.r)),
              child: Icon(Icons.close_rounded, size: 17.sp, color: AppColors.textLabelAlt),
            ),
          ),
        ],
      ),
    );
  }
}
