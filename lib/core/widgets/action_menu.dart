import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import 'app_bottom_sheet.dart';

/// One row in an overflow action menu (the top-right 3-dot sheet, #7).
class MenuAction {
  const MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.sublabel,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;
}

/// Presents the standard overflow action sheet used by every detail page.
/// Pass the page's actions; disabled rows render muted and don't dismiss.
///
/// The chosen action runs **after** the sheet has finished closing, not while
/// it is closing. That ordering matters: a row used to pop the route and then
/// call its callback synchronously, so an action that presented another modal
/// raced the closing menu and could be dismissed on arrival — Reschedule opened
/// a sheet that vanished — and an action that called `context.pop()` could pop
/// the still-live menu route instead of the page behind it. Awaiting the pop
/// first removes the race for every menu in the app.
Future<void> showActionMenu(
  BuildContext context, {
  String? title,
  required List<MenuAction> actions,
}) async {
  final chosen = await showClozrSheet<MenuAction>(
    context: context,
    builder: (ctx) => ClozrActionMenu(title: title, actions: actions),
  );
  chosen?.onTap();
}

class ClozrActionMenu extends StatelessWidget {
  const ClozrActionMenu({super.key, this.title, required this.actions});

  final String? title;
  final List<MenuAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) SheetHeader(title: title!),
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, title == null ? 6.h : 0, 12.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (final a in actions) _row(context, a)],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, MenuAction a) {
    final color = !a.enabled
        ? AppColors.textPlaceholder
        : a.destructive
            ? AppColors.error
            : AppColors.textPrimary;
    return Opacity(
      opacity: a.enabled ? 1 : 0.6,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Hands the action back to [showActionMenu], which runs it once this
        // route has actually closed.
        onTap: a.enabled ? () => Navigator.of(context).pop(a) : null,
        child: Container(
          height: 52.h,
          padding: EdgeInsets.symmetric(horizontal: 10.w),
          child: Row(
            children: [
              Icon(a.icon, size: 20.sp, color: color),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.label,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: color,
                        )),
                    if (a.sublabel != null)
                      Padding(
                        padding: EdgeInsets.only(top: 1.h),
                        child: Text(a.sublabel!,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                            )),
                      ),
                  ],
                ),
              ),
              if (a.enabled && !a.destructive)
                Icon(PhosphorIconsRegular.caretRight,
                    size: 15.sp, color: AppColors.textPlaceholder),
            ],
          ),
        ),
      ),
    );
  }
}
