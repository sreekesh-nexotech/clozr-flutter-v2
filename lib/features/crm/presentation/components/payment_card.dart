import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../application/payments_list_view.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../../domain/entities/payment.dart';
import 'finance_widgets.dart';

/// A payment-record row, carrying the webapp table's cells in card form:
/// PAYMENT (customer, or lead + LEAD badge; "<quote> · <label>" with
/// "Linked to tax invoice"), STATUS (settlement pill), AMOUNT DUE (INCL. GST)
/// with its basis hint and the as-quoted figure, METHOD and DATE. Long-press
/// (wired by the screen) offers the row's View / Delete actions.
class PaymentCard extends ConsumerWidget {
  const PaymentCard({super.key, required this.payment, required this.onTap, this.onLongPress});
  final Payment payment;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookup = ref.watch(crmPartyLookupProvider);
    final pill = settlementPill(payment);
    final pillColor = payToneColor(pill.tone);
    // A customer the directory knows by id wins; otherwise the row's own
    // `customer_name`, then the lead.
    final party = lookup(custId: payment.custId);
    final resolved = (party?.company.isNotEmpty ?? false) ? party!.company : party?.name;
    final who = paymentWho(payment, resolvedCustomer: resolved);
    final hint = amountDueHint(payment);
    final quoted = quotedAmountNote(payment);
    final method = payment.method == '—' ? '—' : payment.method;

    return GestureDetector(
      onLongPress: onLongPress,
      child: ClozrCard(
        radius: 14,
        padding: EdgeInsets.all(13.r),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconChip(icon: payMethodIcon(payment.method)),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      Text(paymentSubLine(payment),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                StatusPill(label: pill.label, color: pillColor),
              ],
            ),
            SizedBox(height: 10.h),
            // AMOUNT DUE (INCL. GST): the figure with its basis hint, then the
            // as-quoted amount when it differs.
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(payMoney(payment.amountDueInclGst),
                    style: AppText.custom(size: 15.5, weight: FontWeight.w800, color: AppColors.navy)),
                if (hint.isNotEmpty) ...[
                  SizedBox(width: 6.w),
                  Flexible(
                    child: Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ),
                ],
              ],
            ),
            if (quoted.isNotEmpty) ...[
              SizedBox(height: 2.h),
              Text(quoted, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textMuted)),
            ],
            const ClozrDivider(margin: EdgeInsets.only(top: 11, bottom: 11)),
            Row(
              children: [
                Expanded(
                  child: Text(method, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                ),
                // The accounting invoice this instalment was billed on, once
                // there is one (`record_summary`, handover §9.1).
                if (payment.recordSummary?.documentNumber != null) ...[
                  StatusPill(label: payment.recordSummary!.documentNumber!, color: AppColors.navy, fontSize: 10.5),
                  SizedBox(width: 8.w),
                ],
                // Webapp DATE cell: coloured like the status pill.
                Text(payment.date, style: AppText.custom(size: 12, weight: FontWeight.w600, color: pillColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// [PayTone] → the app palette.
Color payToneColor(PayTone tone) => switch (tone) {
      PayTone.success => AppColors.success,
      PayTone.warning => AppColors.warning,
      PayTone.danger => AppColors.error,
      PayTone.info => AppColors.blueBright,
      PayTone.muted => AppColors.textMuted,
    };

/// PAY-13 — marks a row whose deal is still a lead (no customer yet).
class LeadBadge extends StatelessWidget {
  const LeadBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
      decoration: BoxDecoration(color: AppColors.tintGrey, borderRadius: BorderRadius.circular(4.r)),
      child: Text('LEAD',
          style: AppText.custom(size: 9.5, weight: FontWeight.w700, color: AppColors.textMuted)
              .copyWith(letterSpacing: 0.3)),
    );
  }
}
