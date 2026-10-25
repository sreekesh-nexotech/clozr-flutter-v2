import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../data/mock/status_meta.dart';
import '../../../application/payment_plan/payment_plan_detail.dart';
import '../../../application/payment_plan/payment_plan_rules.dart';

/// Small shared pieces of the payment-plan / payment-record detail screens.

/// The plan pill: Unpaid / Partial / Completed.
StatusMeta planStatusMeta(String key) => switch (key) {
      'completed' => const StatusMeta('Completed', AppColors.success),
      'partial' => const StatusMeta('Partial', AppColors.warning),
      _ => const StatusMeta('Unpaid', AppColors.textMuted),
    };

/// A record pill from its settlement state. A pending pill keeps the record
/// status colour, so an overdue instalment stays red.
StatusMeta recordStatusMeta(PlanRecord r) {
  final key = recordPillKey(r);
  final label = recordPillLabel(r);
  final color = switch (key) {
    'paid' => AppColors.success,
    'partly_paid' || 'PARTLY_REFUNDED' || 'PARTLY_CREDITED' => AppColors.warning,
    'RECEIPT_REVERSED' => AppColors.error,
    'cancelled' || 'REFUNDED' || 'CREDITED' => AppColors.textMuted,
    _ => r.status == 'overdue' ? AppColors.error : AppColors.warning,
  };
  return StatusMeta(label, color);
}

/// The method's glyph (webapp `METHOD_ICON`).
IconData planMethodIcon(String method) => switch (method.trim().toLowerCase()) {
      'bank_transfer' || 'bank transfer' || 'neft' || 'imps' || 'rtgs' => PhosphorIconsRegular.bank,
      'cheque' => PhosphorIconsRegular.scroll,
      'upi' => PhosphorIconsRegular.deviceMobile,
      'auto_debit' || 'auto-debit' => PhosphorIconsRegular.repeat,
      'card' => PhosphorIconsRegular.creditCard,
      'cash' => PhosphorIconsRegular.wallet,
      '' || '—' => PhosphorIconsRegular.clock,
      _ => PhosphorIconsRegular.wallet,
    };

/// A compact action button: filled navy, or outlined with [color] text.
class PlanButton extends StatelessWidget {
  const PlanButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.color = AppColors.navy,
    this.busy = false,
    this.height = 40,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;
  final Color color;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.white : color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: Opacity(
        opacity: busy || onTap == null ? 0.6 : 1,
        child: Container(
          height: height.h,
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? AppColors.navy : AppColors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: filled ? null : Border.all(color: const Color(0xFFE6E7EA)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 13.sp,
                  height: 13.sp,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(fg)),
                )
              else if (icon != null)
                Icon(icon, size: 14.sp, color: fg),
              if (busy || icon != null) SizedBox(width: 6.w),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The red inline error strip a card shows for a refused write.
class PlanInlineError extends StatelessWidget {
  const PlanInlineError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(color: AppColors.tintRed, borderRadius: BorderRadius.circular(10.r)),
      child: Text(message, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.error, height: 1.4)),
    );
  }
}

/// A muted hint / helper line.
class PlanHint extends StatelessWidget {
  const PlanHint(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(text,
      style: AppText.custom(size: 12, weight: FontWeight.w500, color: color ?? AppColors.textMuted, height: 1.45));
}

/// A tappable date box (label above, "Pick a date" when empty).
class PlanDateField extends StatelessWidget {
  const PlanDateField({
    super.key,
    required this.label,
    required this.isoValue,
    required this.onTap,
    this.errorText,
    this.enabled = true,
  });

  final String label;
  final String isoValue;
  final VoidCallback onTap;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final text = planDate(isoValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
        SizedBox(height: 7.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Container(
            height: 44.h,
            padding: EdgeInsets.symmetric(horizontal: 13.w),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(11.r),
              border: Border.all(color: errorText != null ? AppColors.error : AppColors.borderInput, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(text.isEmpty ? 'Pick a date' : text,
                      style: text.isEmpty ? AppText.body(color: AppColors.textPlaceholder) : AppText.body()),
                ),
                Icon(PhosphorIconsRegular.calendarBlank, size: 16.sp, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
        if (errorText != null) ...[
          SizedBox(height: 5.h),
          Text(errorText!, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.error)),
        ],
      ],
    );
  }
}

/// `YYYY-MM-DD` of a picked day.
String planIsoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The platform date picker seeded from an ISO day (today when blank).
Future<String?> pickPlanDate(BuildContext context, String currentIso, {String? firstIso}) async {
  final now = DateTime.now();
  final current = DateTime.tryParse(currentIso) ?? now;
  final first = DateTime.tryParse(firstIso ?? '') ?? DateTime(now.year - 2);
  final picked = await showDatePicker(
    context: context,
    initialDate: current.isBefore(first) ? first : current,
    firstDate: first,
    lastDate: DateTime(now.year + 6),
  );
  return picked == null ? null : planIsoDay(picked);
}
