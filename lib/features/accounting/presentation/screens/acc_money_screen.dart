import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/application/providers/crm_party_providers.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_settlement.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';
import '../sheets/record_advance_sheet.dart';
import '../sheets/record_receipt_sheet.dart';
import '../sheets/settlement_detail_sheet.dart';
import '../sheets/vendor_payment_sheet.dart';

/// Receipts | Vendor payments | Advances | Credits.
final _moneyTabProvider = StateProvider<String>((ref) => 'receipts');

/// Money (plan §4.8) — customer money in and vendor money out, with the
/// customer advances and credits it leaves behind. Credits are read-only on
/// mobile (applying and refunding them is a web task).
class AccMoneyScreen extends ConsumerWidget {
  const AccMoneyScreen({super.key});

  static const _tabs = {
    'receipts': 'Receipts',
    'payments': 'Vendor payments',
    'advances': 'Advances',
    'credits': 'Credits',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_moneyTabProvider);
    final canPost = ref.watch(accPermProvider('acc_settlement')).create;
    registerAdd(
      ref,
      !canPost
          ? null
          : switch (tab) {
              'payments' => AddAction(label: 'Pay vendor', run: (ctx) => showVendorPaymentSheet(ctx)),
              'advances' => AddAction(label: 'Record advance', run: (ctx) => showRecordAdvanceSheet(ctx)),
              'receipts' => AddAction(label: 'Record receipt', run: (ctx) => showRecordReceiptSheet(ctx)),
              _ => null,
            },
    );
    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            const ScreenTitleRow(title: 'Money'),
            SizedBox(height: 14.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final e in _tabs.entries)
                    TabChip(
                      label: e.value,
                      active: tab == e.key,
                      onTap: () => ref.read(_moneyTabProvider.notifier).state = e.key,
                    ),
                ],
              ),
            ),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AccountingGate(
            child: switch (tab) {
              'payments' => _list<AccVendorPayment>(
                  ref,
                  vendorPaymentsProvider(null),
                  empty: _empty('No vendor payments', 'Payments to vendors show up here.', PhosphorIconsRegular.arrowUp,
                      canPost ? ('Pay vendor', () => showVendorPaymentSheet(context)) : null),
                  row: (p) => _VendorPaymentRow(payment: p),
                ),
              'advances' => _list<AccAdvance>(
                  ref,
                  advancesProvider(null),
                  empty: _empty('No advances', 'Money received before an invoice shows up here.',
                      PhosphorIconsRegular.hourglassMedium,
                      canPost ? ('Record advance', () => showRecordAdvanceSheet(context)) : null),
                  row: (a) => _AdvanceRow(advance: a),
                ),
              'credits' => _list<AccCustomerCredit>(
                  ref,
                  customerCreditsProvider(null),
                  empty: _empty('No customer credits',
                      'Overpayments and credit notes held for a customer show up here.', PhosphorIconsRegular.coins, null),
                  row: (c) => _CreditRow(credit: c),
                ),
              _ => _list<AccReceipt>(
                  ref,
                  receiptsProvider(null),
                  empty: _empty('No receipts', 'Money received from customers shows up here.', PhosphorIconsRegular.arrowDown,
                      canPost ? ('Record receipt', () => showRecordReceiptSheet(context)) : null),
                  row: (r) => _ReceiptRow(receipt: r),
                ),
            },
          ),
        ),
      ],
    );
  }

  Widget _empty(String title, String body, IconData icon, (String, VoidCallback)? cta) => EmptyState(
        icon: icon,
        title: title,
        body: body,
        ctaLabel: cta?.$1,
        ctaIcon: PhosphorIconsBold.plus,
        onCta: cta?.$2,
      );

  Widget _list<T>(
    WidgetRef ref,
    ProviderListenable<AsyncValue<List<T>>> provider, {
    required Widget empty,
    required Widget Function(T) row,
  }) {
    final async = ref.watch(provider);
    Future<void> refresh() async {
      ref.invalidate(receiptsProvider);
      ref.invalidate(vendorPaymentsProvider);
      ref.invalidate(advancesProvider);
      ref.invalidate(customerCreditsProvider);
      await settle([ref.read(receiptsProvider(null).future)]);
    }

    return AsyncStateView<List<T>>(
      value: async,
      onRetry: () => refresh(),
      onRefresh: refresh,
      error: (e, retry) {
        if (e.isAccountingInactive) ref.invalidate(accountingStatusProvider);
        return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          ErrorState.forError(e, onRetry: retry),
        ]);
      },
      data: (items) => items.isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [empty])
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
              itemCount: items.length,
              separatorBuilder: (_, __) => SizedBox(height: 10.h),
              itemBuilder: (_, i) => row(items[i]),
            ),
    );
  }
}

/// The payment card's layout: icon, party + sub line, pill + amount, footer.
class _MoneyCard extends StatelessWidget {
  const _MoneyCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.pill,
    required this.amount,
    required this.footLeft,
    this.footRight,
    this.footRightColor = AppColors.textMuted,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String sub;
  final Widget pill;
  final String amount;
  final String footLeft;
  final String? footRight;
  final Color footRightColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(icon: icon),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 3.h),
                    Text(sub,
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
                  pill,
                  SizedBox(height: 5.h),
                  Text(amount, style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.only(top: 11, bottom: 11)),
          Row(
            children: [
              Expanded(
                child: Text(footLeft,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ),
              if (footRight != null)
                Text(footRight!, style: AppText.custom(size: 12, weight: FontWeight.w600, color: footRightColor)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends ConsumerWidget {
  const _ReceiptRow({required this.receipt});
  final AccReceipt receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = receipt;
    final party = ref.watch(crmPartyLookupProvider)(custId: r.customerId);
    return _MoneyCard(
      icon: PhosphorIconsRegular.arrowDown,
      title: party?.name ?? 'Customer',
      sub: '${formatApiDay(r.date)} · ${label(sourceAccountLabels, r.sourceAccountKind)}'
          '${(r.reference ?? '').isEmpty ? '' : ' · ${r.reference}'}',
      pill: AccPill(StatusMeta$.accPosting, r.status),
      amount: formatMoneyStr(r.amount),
      footLeft: moneyIsZero(r.tdsDeducted) ? label(paymentMethods, r.method) : 'TDS ${formatMoneyStr(r.tdsDeducted)}',
      footRight: moneyIsZero(r.unallocated) ? null : '${formatMoneyStr(r.unallocated)} as credit',
      footRightColor: AppColors.warningDeep,
      onTap: () => showReceiptDetailSheet(context, r),
    );
  }
}

class _VendorPaymentRow extends ConsumerWidget {
  const _VendorPaymentRow({required this.payment});
  final AccVendorPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = payment;
    return _MoneyCard(
      icon: PhosphorIconsRegular.arrowUp,
      title: ref.watch(vendorNameProvider)(p.vendorId) ?? 'Vendor',
      sub: '${formatApiDay(p.date)} · ${label(sourceAccountLabels, p.sourceAccountKind)}'
          '${(p.reference ?? '').isEmpty ? '' : ' · ${p.reference}'}',
      pill: AccPill(StatusMeta$.accPosting, p.status),
      amount: formatMoneyStr(p.amount),
      footLeft: moneyIsZero(p.tdsNow) ? 'No TDS' : 'TDS ${formatMoneyStr(p.tdsNow)}',
      onTap: () => showVendorPaymentDetailSheet(context, p),
    );
  }
}

class _AdvanceRow extends ConsumerWidget {
  const _AdvanceRow({required this.advance});
  final AccAdvance advance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = advance;
    final party = ref.watch(crmPartyLookupProvider)(custId: a.customerId);
    return _MoneyCard(
      icon: PhosphorIconsRegular.hourglassMedium,
      title: party?.name ?? 'Customer',
      sub: [label(supplyNatureLabels, a.supplyNature), if (a.ratePct != null) '${a.ratePct}%', if (a.supply != null) a.supply == 'INTER' ? 'Inter-state' : 'Intra-state']
          .join(' · '),
      pill: AccPill(StatusMeta$.accBalance, a.status),
      amount: formatMoneyStr(a.taxable),
      footLeft: 'Taxable value',
      footRight: '${formatMoneyStr(a.remainingTaxable)} open',
      footRightColor: a.isOpen ? AppColors.blueBright : AppColors.textMuted,
    );
  }
}

class _CreditRow extends ConsumerWidget {
  const _CreditRow({required this.credit});
  final AccCustomerCredit credit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = credit;
    final party = ref.watch(crmPartyLookupProvider)(custId: c.customerId);
    return _MoneyCard(
      icon: PhosphorIconsRegular.coins,
      title: party?.name ?? 'Customer',
      sub: label(creditSourceLabels, c.source),
      pill: AccPill(StatusMeta$.accBalance, c.status),
      amount: formatMoneyStr(c.amount),
      footLeft: 'Apply or refund on the web app',
      footRight: '${formatMoneyStr(c.remaining)} left',
      footRightColor: AppColors.blueBright,
    );
  }
}
