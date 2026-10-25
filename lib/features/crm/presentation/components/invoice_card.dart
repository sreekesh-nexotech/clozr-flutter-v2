import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/payments_list_view.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/view_schema.dart';
import 'finance_widgets.dart';
import 'payment_card.dart' show LeadBadge, payToneColor;

/// A payment-plan row, carrying the webapp table's cells in card form:
/// PAYMENT PLAN (customer — or the lead + LEAD badge — over the quote no.),
/// STATUS (Unpaid grey / Partial amber / Completed green), TYPE and PROGRESS
/// (text over the settled bar), then TOTAL (INCL. GST) and AMOUNT DUE
/// (INCL. GST) in full Indian format with their as-quoted / per-period lines.
///
/// Org-configurable via [schema] — the view-settings engine's `payment` module
/// (`/quotations/payments/schema/?view_type=mobile`), which is this record: the
/// plan header. Empty means "no opinion" and everything renders.
///
/// The identity line (quote no.) is never gated: it is the row's anchor.
class InvoiceCard extends ConsumerWidget {
  const InvoiceCard({
    super.key,
    required this.invoice,
    required this.onTap,
    this.schema = ViewSchema.empty,
    this.leadName,
    this.recordCount,
  });

  final Invoice invoice;
  final VoidCallback onTap;

  /// The org's configured column set for the mobile card.
  final ViewSchema schema;

  /// The quote's lead, for a plan with no customer yet (from its records).
  final String? leadName;

  /// "n/m settled" counts from the plan's records, when known.
  final PlanRecordCount? recordCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookup = ref.watch(crmPartyLookupProvider);
    final statusLabel = (StatusMeta$.invoice[invoice.status] ?? StatusMeta$.invoice['unpaid']!).label;
    final statusColor = payToneColor(planStatusTone(invoice.status));
    final customer = invoiceWho(invoice, lookup);
    final who = planWho(customer == '—' ? null : customer, leadName);
    final figures = planListFigures(invoice);

    // Gated on aliases rather than one exact name: unlike Leads, Customers and
    // Quotes, the Payment module's column set is not written down in
    // `docs-backend/`, so each slot survives if any plausible name for it is
    // visible. Over-showing is the safe direction — a wrong single guess would
    // hide data the org asked to see.
    final showWho = schema.showsAny(const ['customer', 'customer_name', 'lead', 'lead_name']);
    final showStatus = schema.showsAny(const ['status', 'payment_status']);
    final showTotal = schema.showsAny(const ['total_amount', 'amount', 'currency', 'total_incl_gst']);
    final showDue = schema.showsAny(const ['amount_remaining', 'balance_amount', 'amount_due', 'amount_due_incl_gst', 'total_amount', 'amount']);
    final showProgress = schema.showsAny(const ['paid_amount', 'amount_paid', 'balance_amount', 'total_amount', 'amount']);

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
                    if (showWho) ...[
                      Row(
                        children: [
                          Flexible(
                            child: Text(who.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          ),
                          if (who.isLead) ...[SizedBox(width: 6.w), const LeadBadge()],
                        ],
                      ),
                      SizedBox(height: 3.h),
                    ],
                    Text(invoice.quoteId ?? invoice.uuid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (showStatus) ...[
                SizedBox(width: 8.w),
                StatusPill(label: statusLabel, color: statusColor),
              ],
            ],
          ),
          SizedBox(height: 10.h),
          // TYPE · PROGRESS
          Row(
            children: [
              Text(invoice.type,
                  style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              if (showProgress) ...[
                Text('  ·  ', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                Expanded(
                  child: Text(planProgressText(invoice, counts: recordCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                ),
              ],
            ],
          ),
          if (showProgress) ...[
            SizedBox(height: 7.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(9999.r),
              child: LinearProgressIndicator(
                value: invoice.settledPct / 100,
                minHeight: 6.h,
                backgroundColor: AppColors.borderCardSoft,
                valueColor: AlwaysStoppedAnimation(
                    invoice.status == 'unpaid' ? AppColors.borderCardSoft : statusColor),
              ),
            ),
          ],
          if (showTotal || showDue) ...[
            const ClozrDivider(margin: EdgeInsets.only(top: 11, bottom: 11)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showTotal)
                  Expanded(
                    child: _Figure(
                      label: 'TOTAL (INCL. GST)',
                      value: figures.total,
                      sub: figures.totalSub,
                    ),
                  ),
                if (showDue)
                  Expanded(
                    child: _Figure(
                      label: 'AMOUNT DUE (INCL. GST)',
                      value: figures.due,
                      sub: figures.dueSub,
                      alignEnd: showTotal,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One money cell: small caps label, the full-format figure, its sub-line.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.sub, this.alignEnd = false});
  final String label;
  final double value;
  final String sub;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.textMuted)
                .copyWith(letterSpacing: 0.4)),
        SizedBox(height: 3.h),
        Text(payMoney(value), style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.navy)),
        if (sub.isNotEmpty) ...[
          SizedBox(height: 2.h),
          Text(sub, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textMuted)),
        ],
      ],
    );
  }
}
