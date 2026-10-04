import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../crm/presentation/sheets/add_sheet_kit.dart';
import '../components/acc_widgets.dart';

/// The chrome every accounting sheet shares: the standard sheet header, a
/// scrolling body with the fields spaced as the Record payment sheet spaces
/// them, the inline [ConflictBanner] when the last submit was refused, and the
/// sticky submit bar — busy while in flight, disabled when offline.
class AccSheetScaffold extends ConsumerWidget {
  const AccSheetScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
    this.submitIcon = PhosphorIconsBold.check,
    this.busy = false,
    this.error,
    this.errorAction,
    this.onErrorAction,
    this.posts = true,
    this.submitEnabled = true,
    this.busyLabel = 'Posting…',
  });

  final String title;
  final List<Widget> children;
  final String submitLabel;
  final IconData submitIcon;
  final VoidCallback onSubmit;
  final bool busy;
  final AppError? error;
  final String? errorAction;
  final VoidCallback? onErrorAction;

  /// Whether submitting posts to the ledger (then it needs a connection).
  final bool posts;
  final bool submitEnabled;
  final String busyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = isOnline(ref);
    final blocked = (posts && !online) || !submitEnabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: title, onClose: () => Navigator.of(context).maybePop()),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null) ...[
                  ConflictBanner(error: error!, actionLabel: errorAction, onAction: onErrorAction),
                  SizedBox(height: 13.h),
                ],
                for (int i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(height: 13.h),
                  children[i],
                ],
                if (posts && !online) const OfflineNote(),
                SizedBox(height: 6.h),
              ],
            ),
          ),
        ),
        Opacity(
          opacity: blocked && !busy ? 0.5 : 1,
          child: IgnorePointer(
            ignoring: blocked,
            child: SheetSubmitBar(
              label: submitLabel,
              icon: submitIcon,
              onTap: onSubmit,
              busy: busy,
              busyLabel: busyLabel,
            ),
          ),
        ),
      ],
    );
  }
}

/// A confirm dialog in the app's style ([confirmDiscard]'s look). [destructive]
/// paints the confirm action red. Resolves true on confirm.
Future<bool> confirmAcc(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      title: Text(title, style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
      content: Text(body, style: AppText.body(color: AppColors.textMuted).copyWith(height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel', style: AppText.bodyStrong(color: AppColors.textLabelAlt)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel,
              style: AppText.bodyStrong(color: destructive ? AppColors.error : AppColors.navy)),
        ),
      ],
    ),
  );
  return res ?? false;
}
