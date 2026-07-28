import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// Full-screen create-form chrome: an "✕ Title" header, a scrolling body and a
/// sticky primary CTA at the bottom (disabled when [ctaEnabled] is false).
class OpsFormScaffold extends StatelessWidget {
  const OpsFormScaffold({
    super.key,
    required this.title,
    required this.ctaLabel,
    required this.ctaEnabled,
    required this.onClose,
    required this.onSubmit,
    required this.children,
  });

  final String title;
  final String ctaLabel;
  final bool ctaEnabled;
  final VoidCallback onClose;
  final VoidCallback onSubmit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgApp,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 12.h),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Padding(
                    padding: EdgeInsets.only(right: 12.w),
                    child: Icon(PhosphorIconsBold.x, size: 20.sp, color: AppColors.textPrimary),
                  ),
                ),
                Text(title, style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 24.h),
              children: children,
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 26.h),
            decoration: const BoxDecoration(
              color: AppColors.white,
              border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
            ),
            child: GestureDetector(
              onTap: ctaEnabled ? onSubmit : null,
              child: Container(
                height: 50.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ctaEnabled ? AppColors.navy : const Color(0xFFC7CBD3),
                  borderRadius: BorderRadius.circular(13.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.plus, size: 15.sp, color: AppColors.white),
                    SizedBox(width: 8.w),
                    Text(ctaLabel, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An uppercase section label used to group edit-form fields.
class OpsSectionLabel extends StatelessWidget {
  const OpsSectionLabel(this.text, {super.key, this.first = false});
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2.w, first ? 8.h : 22.h, 2.w, 12.h),
      child: Text(text.toUpperCase(),
          style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
    );
  }
}

/// Full-screen edit-form chrome: a caret-back header with a sub-line, a
/// scrolling body and a sticky Cancel / Save bar. [onClose] receives a
/// discard-confirmation flow via [confirmDiscard].
class OpsEditScaffold extends StatelessWidget {
  const OpsEditScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.onSave,
    required this.children,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 14.h),
            decoration: const BoxDecoration(
              color: AppColors.white,
              border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Container(
                    width: 38.w,
                    height: 38.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: const Color(0xFFE6E7EA)),
                    ),
                    child: Icon(PhosphorIconsBold.caretLeft, size: 17.sp, color: AppColors.textBody),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                      Text(subtitle, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 20.h),
              children: children,
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
            decoration: const BoxDecoration(
              color: AppColors.white,
              border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 100.w,
                    height: 48.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: const Color(0xFFE6E7EA)),
                    ),
                    child: Text('Cancel', style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: GestureDetector(
                    onTap: onSave,
                    child: Container(
                      height: 48.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(12.r),
                        boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(0.22), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.white),
                          SizedBox(width: 8.w),
                          Text('Save changes', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a discard-changes confirmation. Returns true if the user discards.
Future<bool> confirmDiscard(BuildContext context) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      title: Text('Discard changes?', style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
      content: Text('Your edits will be lost.', style: AppText.body(color: AppColors.textMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Keep editing', style: AppText.bodyStrong(color: AppColors.textLabelAlt))),
        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Discard', style: AppText.bodyStrong(color: AppColors.error))),
      ],
    ),
  );
  return res ?? false;
}

/// Convenience: pops the route when the user confirms discarding.
Future<void> handleEditClose(BuildContext context, {required bool dirty}) async {
  if (!dirty) {
    context.pop();
    return;
  }
  final discard = await confirmDiscard(context);
  if (discard && context.mounted) context.pop();
}
