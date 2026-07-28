import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/quotes_providers.dart';
import '../../domain/entities/quote.dart';
import 'finance_widgets.dart';

/// A quote list row: file icon, who + "#id · N items", status pill + amount, and
/// a footer with the validity line and payment type.
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.quote, required this.onTap});
  final Quote quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.quote[quote.status] ?? StatusMeta$.quote['draft']!;
    final itemsLabel = '${quote.items.length} ${quote.items.length == 1 ? 'item' : 'items'}';
    final validLabel = quote.valid == '—' ? 'Draft — not issued' : 'Valid till ${quote.valid}';

    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(icon: PhosphorIconsRegular.fileText),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quoteWho(quote),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 3.h),
                    Text('#${quote.id} · $itemsLabel',
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
                  Text(quote.amount, style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.only(top: 11, bottom: 11)),
          Row(
            children: [
              Expanded(
                child: Text(validLabel, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ),
              Text(quote.payType, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            ],
          ),
        ],
      ),
    );
  }
}
