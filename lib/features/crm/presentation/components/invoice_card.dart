import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/invoices_providers.dart';
import '../../domain/entities/invoice.dart';
import 'finance_widgets.dart';

/// An invoice list row: receipt icon, who + "id · #quote · type", status pill +
/// total, then an installment progress bar and a "settled / balance" footer.
class InvoiceCard extends StatelessWidget {
  const InvoiceCard({super.key, required this.invoice, required this.onTap});
  final Invoice invoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.invoice[invoice.status] ?? StatusMeta$.invoice['partial']!;

    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(icon: PhosphorIconsRegular.receipt),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(invoiceWho(invoice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 3.h),
                    Text('${invoice.id} · #${invoice.quoteId ?? '—'} · ${invoice.type}',
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
                  Text(invoice.total, style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(9999.r),
            child: LinearProgressIndicator(
              value: invoice.progress,
              minHeight: 7.h,
              backgroundColor: AppColors.borderCardSoft,
              valueColor: AlwaysStoppedAnimation(meta.color),
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: Text('${invoice.settled}/${invoice.of} settled',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ),
              Text('Balance ${invoice.balance}',
                  style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
            ],
          ),
        ],
      ),
    );
  }
}
