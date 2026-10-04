import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../crm/application/providers/crm_party_providers.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../config/accounting_copy.dart';
import 'acc_widgets.dart';

/// The icon for where a document came from.
IconData documentSourceIcon(AccDocument d) => switch (d.sourceType) {
      'PLAN_RECORD' || 'PERIODIC' || 'MILESTONE' => PhosphorIconsRegular.calendarCheck,
      'TICKET' => PhosphorIconsRegular.ticket,
      'EXPENSE_FORM' => PhosphorIconsRegular.shoppingCart,
      _ => d.docType == 'CREDIT_NOTE' ? PhosphorIconsRegular.arrowUUpLeft : PhosphorIconsRegular.receipt,
    };

/// The party a document is with, by name where the app knows it. Document rows
/// carry ids only (§12.5); the snapshot has the name once issued.
String documentPartyName(WidgetRef ref, AccDocument d) {
  if (d.isInward) {
    return ref.watch(vendorNameProvider)(d.vendorId) ?? _snapshotName(d) ?? 'Vendor';
  }
  final party = ref.watch(crmPartyLookupProvider)(custId: d.customerId);
  return party?.name ?? _snapshotName(d) ?? (d.customerId == null ? 'No customer yet' : 'Customer');
}

String? _snapshotName(AccDocument d) {
  final n = d.partySnapshot['name'] ?? d.partySnapshot['legal_name'];
  return n is String && n.isNotEmpty ? n : null;
}

/// A document list row, in the payment card's layout: source icon, number +
/// party · date, status pill + total, and a footer with the payment state and
/// what is still open.
class DocumentCard extends ConsumerWidget {
  const DocumentCard({super.key, required this.document, required this.onTap});

  final AccDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = document;
    final open = d.isInward ? (d.payable ?? d.openBalance) : d.openBalance;
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(icon: documentSourceIcon(d)),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.isInward && (d.vendorInvoiceNo ?? '').isNotEmpty
                            ? '${d.displayNumber} · ${d.vendorInvoiceNo}'
                            : d.displayNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 3.h),
                    Text('${documentPartyName(ref, d)} · ${formatApiDay(d.documentDate)}',
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
                  DocStatusPill(d.status),
                  SizedBox(height: 5.h),
                  Text(formatMoneyStr(d.grandTotal),
                      style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.only(top: 11, bottom: 11)),
          Row(
            children: [
              Expanded(
                child: Text(
                  d.isDraft ? '${label(docTypeLabels, d.docType)} · estimated' : label(docTypeLabels, d.docType),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted),
                ),
              ),
              if (d.isIssued && !moneyIsZero(open)) ...[
                Text('Open ${formatMoneyStr(open)}',
                    style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.error)),
                SizedBox(width: 8.w),
              ],
              if (d.isIssued) PaymentStatePill(d.paymentState),
            ],
          ),
        ],
      ),
    );
  }
}
