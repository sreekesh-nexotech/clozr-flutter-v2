import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../application/providers/shell_providers.dart';

/// The app-wide toast, mounted **above the navigator** rather than inside the
/// shell's Stack.
///
/// Position is the whole point. The shell is a routed screen, while every
/// bottom sheet opens with `useRootNavigator: true` — so a toast raised from a
/// sheet (Add task, Add follow-up, Log call…) rendered *underneath* that sheet
/// and its scrim, and the user saw nothing at all. Mounting it in the
/// `MaterialApp.builder` puts it over the navigator, so it is visible whatever
/// is on screen.
class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    if (toast == null) return const SizedBox.shrink();

    // A failure is a different thing from a confirmation: warning glyph in
    // amber instead of the green tick, so a refusal cannot be mistaken for the
    // action having gone through.
    final (icon, tint) = toast.isError
        ? (PhosphorIconsFill.warningCircle, AppColors.warning)
        : (PhosphorIconsFill.checkCircle, AppColors.toastCheck);

    // Sit above the keyboard whenever it is up.
    //
    // This overlay is mounted in `MaterialApp.builder`, above every Scaffold, so
    // its MediaQuery still carries the true `viewInsets` — the shell's resizing
    // Scaffold has not stripped them yet (see [KeyboardVisibility]). The offset
    // used to be `106.h + viewPadding.bottom`, and `viewPadding` is the
    // safe-area inset, which does **not** change when the keyboard opens: the
    // toast stayed 106dp off the bottom and the keyboard covered it outright.
    // That hid exactly the messages that matter most, since validation errors
    // are raised while a field is focused.
    //
    // With the keyboard up the 106dp bottom-nav allowance is not needed either
    // — the shell hides the nav bar then — and `viewInsets.bottom` already spans
    // the safe area, so adding `viewPadding` on top would double-count it.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = keyboard > 0
        ? keyboard + 16.h
        : 106.h + MediaQuery.viewPaddingOf(context).bottom;

    return Positioned(
      bottom: bottom,
      left: 0,
      right: 0,
      child: IgnorePointer(
        // The toast carries whatever the backend said, and a validation error
        // is a sentence, not a word ("A task must have at least one note
        // before it can be completed."). Without a width bound the row simply
        // grew past the screen and overflowed; it has to wrap instead.
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 17.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withOpacity(0.34),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18.sp, color: tint),
                  SizedBox(width: 9.w),
                  // Flexible, not Expanded: a short message still gets a
                  // snug pill rather than one stretched to the full width.
                  Flexible(
                    child: Text(
                      toast.text,
                      // Bounded so a pathological message cannot cover the
                      // screen, but generous enough that no realistic
                      // validation error is cut off.
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(
                              size: 13, weight: FontWeight.w600, color: AppColors.white)
                          .copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
