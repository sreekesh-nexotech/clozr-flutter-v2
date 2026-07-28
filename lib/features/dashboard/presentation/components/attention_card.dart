import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/entities/dash_colors.dart';
import '../../domain/entities/dashboard_models.dart';

/// A CRM "Attention Needed" tile (2×2 grid): a big number, a label, then a
/// delta pill (green/red/steady-grey) and a note on the right.
class AttentionCard extends StatelessWidget {
  const AttentionCard({super.key, required this.card, this.onTap});
  final DashAttentionCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14.r),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(15.r),
          border: Border.all(color: AppColors.borderCardSoft),
          boxShadow: [
            BoxShadow(color: const Color(0xFF101828).withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1)),
            BoxShadow(color: const Color(0xFF101828).withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(card.value,
                style: AppText.custom(size: 24, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
            SizedBox(height: 2.h),
            Text(card.label,
                style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _deltaPill(),
                Flexible(
                  child: Text(card.note,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 11, weight: FontWeight.w600, color: card.noteColor)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _deltaPill() {
    final Color bg, fg;
    if (card.neutral) {
      bg = DashColors.chipGrey;
      fg = DashColors.textMid;
    } else if (card.positive) {
      bg = DashColors.tintGreen;
      fg = DashColors.green;
    } else {
      bg = DashColors.tintRed;
      fg = DashColors.red;
    }
    final icon = switch (card.arrow) {
      DashTrendArrow.up => PhosphorIconsBold.arrowUp,
      DashTrendArrow.down => PhosphorIconsBold.arrowDown,
      DashTrendArrow.flat => PhosphorIconsBold.arrowRight,
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.sp, color: fg),
          SizedBox(width: 3.w),
          Text(card.delta, style: AppText.custom(size: 11, weight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}
