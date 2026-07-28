import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/payments_providers.dart';
import '../../domain/entities/payment.dart';
import 'finance_widgets.dart';

/// A payment list row: method icon, customer + "#id · label", status pill +
/// amount, and a footer with the method and the status-coloured date.
class PaymentCard extends StatelessWidget {
  const PaymentCard({super.key, required this.payment, required this.onTap});
  final Payment payment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.payment[payment.status] ?? StatusMeta$.payment['due']!;
    final methodLabel = payment.method == '—' ? 'Not set' : payment.method;

    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(icon: payMethodIcon(payment.method)),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(paymentTitle(payment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 3.h),
                    Text('${payment.id} · ${payment.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusPill.meta(meta),
                  SizedBox(height: 5.h),
                  Text(payment.amount, style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.only(top: 11, bottom: 11)),
          Row(
            children: [
              Expanded(
                child: Text(methodLabel, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ),
              Text(payment.date,
                  style: AppText.custom(size: 12, weight: FontWeight.w600, color: paymentDateColor(payment.status))),
            ],
          ),
        ],
      ),
    );
  }
}
