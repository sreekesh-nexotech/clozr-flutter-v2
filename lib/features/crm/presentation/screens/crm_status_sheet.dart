import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';

/// Opens the shared "update status" bottom sheet: a list of status options
/// (colour dot + label + a tick on the current one). Selecting a status closes
/// the sheet and, if [onSelect] is provided, hands the chosen key to the caller
/// (which persists the change + toasts). When [onSelect] is null it falls back
/// to a plain "Status set to …" toast, leaving seed data untouched.
void showCrmStatusSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required List<String> options,
  required Map<String, StatusMeta> meta,
  required String current,
  void Function(String key)? onSelect,
}) {
  showClozrSheet<void>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: title, onClose: () => Navigator.of(ctx).pop()),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
            children: [
              for (final k in options)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (onSelect != null) {
                      onSelect(k);
                    } else {
                      ref.read(toastProvider.notifier).show('Status set to ${meta[k]!.label}');
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 13.h),
                    decoration: BoxDecoration(
                      color: current == k ? const Color(0xFFF6F8FB) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(
                      children: [
                        Container(width: 11.w, height: 11.w, decoration: BoxDecoration(color: meta[k]!.color, shape: BoxShape.circle)),
                        SizedBox(width: 12.w),
                        Expanded(child: Text(meta[k]!.label, style: AppText.bodyStrong())),
                        if (current == k) Icon(PhosphorIconsBold.check, size: 18.sp, color: AppColors.success),
                      ],
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
