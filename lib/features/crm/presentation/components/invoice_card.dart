import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/view_schema.dart';
import 'finance_widgets.dart';

/// An invoice list row: receipt icon, who + "id · #quote · type", status pill +
/// total, then an installment progress bar and a "settled / balance" footer.
///
/// Org-configurable via [schema] — the view-settings engine's `payment` module
/// (`/quotations/payments/schema/?view_type=mobile`), which is this record: the
/// invoice header. Empty means "no opinion" and everything renders.
///
/// The identity line (`id · #quote · type`) is never gated: it is the row's
/// anchor, and a card with no identifier is not a row.
class InvoiceCard extends ConsumerWidget {
  const InvoiceCard({
    super.key,
    required this.invoice,
    required this.onTap,
    this.schema = ViewSchema.empty,
  });

  final Invoice invoice;
  final VoidCallback onTap;

  /// The org's configured column set for the mobile card.
  final ViewSchema schema;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = StatusMeta$.invoice[invoice.status] ?? StatusMeta$.invoice['partial']!;
    final lookup = ref.watch(crmPartyLookupProvider);

    // Gated on aliases rather than one exact name: unlike Leads, Customers and
    // Quotes, the Payment module's column set is not written down in
    // `docs-backend/`, so each slot survives if any plausible name for it is
    // visible. Over-showing is the safe direction — a wrong single guess would
    // hide data the org asked to see.
    final showWho = schema.showsAny(const ['customer', 'customer_name', 'lead', 'lead_name']);
    final showStatus = schema.showsAny(const ['status', 'payment_status']);
    final showTotal = schema.showsAny(const ['total_amount', 'amount', 'currency']);
    final showProgress = schema.showsAny(const ['paid_amount', 'balance_amount', 'total_amount', 'amount']);
    final showSideColumn = showStatus || showTotal;

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
                    if (showWho) ...[
                      Text(invoiceWho(invoice, lookup),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                      SizedBox(height: 3.h),
                    ],
                    Text('${invoice.id} · #${invoice.quoteId ?? '—'} · ${invoice.type}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (showSideColumn) ...[
                SizedBox(width: 8.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (showStatus) StatusPill.meta(meta),
                    if (showTotal) ...[
                      SizedBox(height: 5.h),
                      Text(invoice.total, style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                    ],
                  ],
                ),
              ],
            ],
          ),
          if (showProgress) ...[
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
          ],
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
