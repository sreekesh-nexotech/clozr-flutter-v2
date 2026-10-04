import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/presentation/components/crm_detail_parts.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../../domain/entities/acc_settlement.dart';
import '../config/accounting_copy.dart';
import 'acc_widgets.dart';

/// The customer detail's Accounting tab (plan §5.3): what they owe, what they
/// paid, their open advances and credits, and a link to the statement. Built
/// to sit inside the customer activity card like the other tabs — rows, not
/// cards.
class CustomerAccountingTab extends ConsumerWidget {
  const CustomerAccountingTab({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(accPermProvider('acc_document')).read;
    final settle = ref.watch(accPermProvider('acc_settlement')).read;
    final reports = ref.watch(accPermProvider('acc_report')).read;
    final invoices = docs ? ref.watch(documentsForCustomerProvider(customerId)) : null;
    final receipts = settle ? ref.watch(receiptsProvider(customerId)) : null;
    final advances = settle ? ref.watch(advancesProvider(customerId)).valueOrNull : null;
    final credits = settle ? ref.watch(customerCreditsProvider(customerId)).valueOrNull : null;

    final openAdvances = [for (final a in advances ?? const <AccAdvance>[]) if (a.isOpen) a];
    final openCredits = [
      for (final c in credits ?? const <AccCustomerCredit>[])
        if (c.status == 'OPEN' || c.status == 'PARTIALLY_APPLIED') c,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (docs) ...[
          _heading('Invoices'),
          ...switch (invoices) {
            AsyncData(:final value) when value.isEmpty => [_muted('No invoices yet.')],
            AsyncData(:final value) => [for (final d in value.take(8)) _docRow(context, d)],
            AsyncError() => [_muted('Could not load invoices.')],
            _ => [_muted('Loading…')],
          },
        ],
        if (settle) ...[
          _heading('Receipts'),
          ...switch (receipts) {
            AsyncData(:final value) when value.isEmpty => [_muted('No receipts yet.')],
            AsyncData(:final value) => [for (final r in value.take(5)) _receiptRow(r)],
            AsyncError() => [_muted('Could not load receipts.')],
            _ => [_muted('Loading…')],
          },
          if (openAdvances.isNotEmpty || openCredits.isNotEmpty) ...[
            _heading('Open balances in their favour'),
            for (final a in openAdvances)
              _line('Advance · ${label(supplyNatureLabels, a.supplyNature)}', formatMoneyStr(a.remainingTaxable),
                  pill: AccPill(StatusMeta$.accBalance, a.status)),
            for (final c in openCredits)
              _line('Credit · ${label(creditSourceLabels, c.source)}', formatMoneyStr(c.remaining),
                  pill: AccPill(StatusMeta$.accBalance, c.status)),
          ],
        ],
        if (reports) ...[
          SizedBox(height: 12.h),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('${Routes.accReport}?kind=customer_statement&party=$customerId'),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.fileText, size: 16.sp, color: AppColors.blueBright),
                SizedBox(width: 6.w),
                Text('View statement', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
              ],
            ),
          ),
        ],
        if (!docs && !settle && !reports)
          const DetailTabEmpty(
            icon: PhosphorIconsRegular.lock,
            title: 'No accounting access',
            body: 'Your role cannot see this customer\'s accounts.',
          ),
      ],
    );
  }

  Widget _heading(String t) => Padding(
        padding: EdgeInsets.only(top: 12.h, bottom: 4.h),
        child: Text(t.toUpperCase(),
            style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
      );

  Widget _muted(String t) => Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: Text(t, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
      );

  Widget _docRow(BuildContext context, AccDocument d) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.accDocumentDetail}?id=${d.id}'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.displayNumber, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(
                    d.isIssued && !moneyIsZero(d.openBalance)
                        ? '${formatApiDay(d.documentDate)} · open ${formatMoneyStr(d.openBalance)}'
                        : formatApiDay(d.documentDate),
                    style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatMoneyStr(d.grandTotal), style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
                SizedBox(height: 4.h),
                d.isIssued ? PaymentStatePill(d.paymentState) : DocStatusPill(d.status),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(AccReceipt r) => _line(
        '${formatApiDay(r.date)} · ${label(paymentMethods, r.method ?? r.sourceAccountKind?.toLowerCase())}',
        formatMoneyStr(r.amount),
        pill: AccPill(StatusMeta$.accPosting, r.status),
      );

  Widget _line(String left, String right, {Widget? pill}) => Container(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          children: [
            Expanded(child: Text(left, style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBody))),
            if (pill != null) ...[pill, SizedBox(width: 8.w)],
            Text(right, style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
          ],
        ),
      );
}

/// "B2B · <GSTIN>" under a customer's name once their tax profile says they
/// are registered. Renders nothing otherwise, or when accounting is off.
class CustomerB2bBadge extends ConsumerWidget {
  const CustomerB2bBadge({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(accountingActiveProvider) || !ref.watch(accPermProvider('acc_setup')).read) {
      return const SizedBox.shrink();
    }
    final p = ref.watch(partyTaxProfileProvider((kind: 'customer', id: customerId))).valueOrNull;
    if (p == null || !p.isB2b) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 5.h),
      child: StatusPill(label: 'B2B · ${p.gstin}', color: AppColors.navy),
    );
  }
}
