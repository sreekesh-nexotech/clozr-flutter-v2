import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../../domain/entities/payment.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../components/crm_async.dart';
import '../components/finance_widgets.dart';
import '../components/record_payment_sheet.dart';
import '../../../../core/utils/money_format.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/presentation/components/acc_widgets.dart';
import '../../../accounting/presentation/config/accounting_copy.dart';

/// Payment detail — header (amount + status + optional "Mark as paid"), related
/// links, payment detail rows, activity and notes.
class PaymentDetailScreen extends ConsumerWidget {
  const PaymentDetailScreen({super.key});

  /// Pull-to-refresh: the payment list this record is read out of, the invoices
  /// its linked-invoice card reads, and the party directory.
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(paymentsProvider);
    ref.invalidate(invoicesProvider);
    ref.invalidate(crmPartyLookupProvider);
    await settle([
      ref.read(paymentsProvider.future),
      ref.read(invoicesProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(paymentsProvider);

    Widget scaffold(Widget child) => Container(
          color: AppColors.bgDetail,
          child: Column(
            children: [
              DetailAppBar(section: 'Payment', onBack: () => context.pop()),
              Expanded(child: child),
            ],
          ),
        );

    return async.when(
      loading: () => scaffold(const DetailSkeleton()),
      error: (e, _) => scaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => ref.invalidate(paymentsProvider)),
      ),
      data: (_) => _buildPayment(context, ref, id, scaffold),
    );
  }

  Widget _buildPayment(
    BuildContext context,
    WidgetRef ref,
    String id,
    Widget Function(Widget) scaffold,
  ) {
    final payment = ref.watch(paymentByIdProvider(id));
    if (payment == null) {
      return scaffold(const EmptyState(
        icon: PhosphorIconsRegular.wallet,
        title: 'Payment not found',
        body: 'This payment may have been removed or you no longer have access to it.',
      ));
    }

    final lookup = ref.watch(crmPartyLookupProvider);
    final meta = StatusMeta$.payment[payment.status] ?? StatusMeta$.payment['due']!;
    final owner = MockUsers.of(payment.owner);
    final cust = lookup(custId: payment.custId);
    final linkedInvoice = payment.invId == null ? null : ref.watch(invoiceByIdProvider(payment.invId!));
    final canMarkPaid = payment.status != 'paid';

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Payment',
            name: paymentTitle(payment, lookup),
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => ref.read(toastProvider.notifier).show('Payment actions'),
            ),
          ),
          Expanded(
            child: AppRefresh(
              onRefresh: () => _refresh(ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headerCard(context, ref, payment, meta, canMarkPaid),
                SizedBox(height: 14.h),
                _relatedCard(context, payment, cust, linkedInvoice?.quoteId),
                SizedBox(height: 14.h),
                _detailsCard(payment, meta, owner),
                SizedBox(height: 14.h),
                if (payment.recordSummary != null) ...[
                  _accountingCard(context, payment),
                  SizedBox(height: 14.h),
                ],
                FinanceCard(
                  title: 'Activity',
                  child: Padding(
                    padding: EdgeInsets.only(top: 6.h),
                    child: ActivityTimeline(entries: _activity(payment, owner.name)),
                  ),
                ),
                SizedBox(height: 14.h),
                NotesCard(onSend: (_) => ref.read(toastProvider.notifier).show('Note added')),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Settles this installment for real — `PATCH /quotations/payment-records/`,
  /// the same call the Invoice screen's "Settle now" row and the Record payment
  /// sheet make.
  ///
  /// This button used to be a bare toast: it said "Payment marked as paid" and
  /// wrote nothing, so the pill still read unpaid after a reload. Two other
  /// places in the app already did the real write, which made this the odd one
  /// out rather than a deliberate stub.
  Future<void> _markPaid(BuildContext context, WidgetRef ref, Payment payment) async {
    // With accounting on, marking paid posts a receipt: it needs the date the
    // money arrived, any TDS withheld and the bank it landed in — which is
    // exactly what the sheet asks for. A one-tap "today, in full, no bank"
    // write would book the wrong period and the wrong cash.
    if (ref.read(accountingActiveProvider)) {
      await showRecordPaymentSheet(context, invoiceId: payment.invId, recordId: payment.id);
      return;
    }
    final prev = ref.read(paidOverrideProvider);
    ref.read(paidOverrideProvider.notifier).state = {...prev, payment.id};

    if (ApiConfig.apiEnabled) {
      try {
        await ref.read(paymentsRepositoryProvider).markRecordPaid(
              payment.id,
              amountPaid: payment.amountExact.isNotEmpty ? payment.amountExact : null,
            );
      } on AppError catch (e) {
        // Put the optimistic flip back, so the pill cannot claim a payment the
        // server refused.
        ref.read(paidOverrideProvider.notifier).state = {...prev};
        ref.read(toastProvider.notifier).showError(e.message);
        return;
      }
      // The server recalculates the parent invoice, so both lists are stale.
      ref.invalidate(paymentsProvider);
      ref.invalidate(invoicesProvider);
    }
    ref.read(toastProvider.notifier).show('Payment marked as paid');
  }

  Widget _headerCard(BuildContext context, WidgetRef ref, Payment payment, StatusMeta meta, bool canMarkPaid) {
    final lookup = ref.watch(crmPartyLookupProvider);
    return FinanceCard(
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
                        Text(payment.amount,
                            style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
                        SizedBox(width: 8.w),
                        StatusPill.meta(meta),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text(paymentTitle(payment, lookup),
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 3.h),
                    Text('${payment.id} · ${payment.label}',
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
            ],
          ),
          if (canMarkPaid) ...[
            const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
            GestureDetector(
              onTap: () => _markPaid(context, ref, payment),
              child: Container(
                height: 46.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.check, size: 15.sp, color: AppColors.white),
                    SizedBox(width: 8.w),
                    Text('Mark as paid', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.white)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _relatedCard(BuildContext context, Payment payment, CrmParty? cust, String? invoiceQuoteId) {
    final chips = <Widget>[
      if (cust != null)
        _relChip(
          kind: 'Customer · #${cust.id}',
          name: cust.company,
          onTap: () => context.push('${Routes.customerDetail}?id=${cust.id}'),
        ),
      if (payment.invId != null)
        _relChip(
          kind: 'Invoice · ${payment.invId}',
          name: '#${invoiceQuoteId ?? '—'}',
          onTap: () => context.push('${Routes.invoiceDetail}?id=${payment.invId}'),
        ),
    ];

    return FinanceCard(
      title: 'RELATED',
      child: Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Column(
          children: [
            for (int i = 0; i < chips.length; i++) ...[
              if (i > 0) SizedBox(height: 8.h),
              chips[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _relChip({required String kind, required String name, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.borderCardSoft),
        ),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.arrowSquareOut, size: 16.sp, color: AppColors.blueBright),
            SizedBox(width: 11.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind, style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
                  SizedBox(height: 1.h),
                  Text(name, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
            ),
            Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
          ],
        ),
      ),
    );
  }

  Widget _detailsCard(Payment payment, StatusMeta meta, AppUser owner) {
    return FinanceCard(
      title: 'Payment details',
      child: Column(
        children: [
          MetaRow(label: 'Amount', value: payment.amountExact.isEmpty ? payment.amount : formatMoneyStr(payment.amountExact)),
          MetaRow(label: 'Status', value: meta.label),
          // Only once something was withheld: on an ordinary receipt cash and
          // the contracted amount are the same figure.
          if (payment.hasDeductions) ...[
            MetaRow(label: 'Cash received', value: formatMoneyStr(payment.paidCashNum)),
            if (payment.tdsNum > 0) MetaRow(label: 'TDS withheld', value: formatMoneyStr(payment.tdsNum)),
            if (payment.gstTdsNum > 0) MetaRow(label: 'GST TDS', value: formatMoneyStr(payment.gstTdsNum)),
            if (payment.gstTcsNum > 0) MetaRow(label: 'GST TCS', value: formatMoneyStr(payment.gstTcsNum)),
            if (payment.bankChargeNum > 0) MetaRow(label: 'Bank charge', value: formatMoneyStr(payment.bankChargeNum)),
            MetaRow(
                label: 'Settled value',
                value: formatMoneyStr(payment.paidCashNum + payment.deductionsNum)),
          ],
          if (payment.treatAs != null)
            MetaRow(label: 'Booked as', value: label(const {'ADVANCE': 'Advance', 'CUSTOMER_CREDIT': 'Customer credit'}, payment.treatAs)),
          MetaRow(label: 'Method', value: payment.method == '—' ? 'Not set' : payment.method),
          MetaRow(label: 'Type', value: payment.label),
          MetaRow(label: 'Date', value: payment.date),
          MetaRow(label: 'Reference', value: '—'),
          MetaRow(label: 'Recorded by', value: owner.name),
          MetaRow(label: 'Invoice', value: payment.invId ?? '—', last: true),
          SizedBox(height: 13.h),
          Row(
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: owner.color, shape: BoxShape.circle),
                child: Text(owner.initials, style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.white)),
              ),
              SizedBox(width: 11.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(owner.name, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text('Collection owner', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What the ledger made of this instalment: its invoice and its receipt.
  Widget _accountingCard(BuildContext context, Payment payment) {
    final s = payment.recordSummary!;
    return FinanceCard(
      title: 'Accounting',
      child: Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Column(
          children: [
            if (s.hasDocument)
              _relChip(
                kind: 'Invoice · ${label(const {'DRAFT': 'Draft', 'ISSUED': 'Issued', 'CANCELLED': 'Cancelled', 'VOID_DRAFT': 'Void'}, s.documentStatus)}'
                    '${s.documentPaymentState == null || s.documentPaymentState == 'NA' ? '' : ' · ${label(const {'UNPAID': 'Unpaid', 'PARTIAL': 'Part paid', 'PAID': 'Paid'}, s.documentPaymentState)}'}',
                name: s.documentNumber ?? 'Draft',
                onTap: () => context.push('${Routes.accDocumentDetail}?id=${s.documentId}'),
              ),
            if (s.hasDocument && s.hasReceipt) SizedBox(height: 8.h),
            if (s.hasReceipt)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppColors.borderCardSoft),
                ),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.receipt, size: 16.sp, color: AppColors.success),
                    SizedBox(width: 11.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('RECEIPT · ${s.receiptStatus ?? ''}'.trim(),
                              style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
                          SizedBox(height: 1.h),
                          Text('${formatMoneyStr(s.receiptAmount)} · ${formatApiDay(s.receiptDate)}',
                              style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (payment.status == 'paid') ...[
              SizedBox(height: 10.h),
              const AccInfoBanner('Changing the amount, TDS or date of a paid instalment reverses its receipt and posts it again.'),
            ],
          ],
        ),
      ),
    );
  }

  List<ActivityEntry> _activity(Payment payment, String ownerName) {
    final paid = payment.status == 'paid';
    return [
      ActivityEntry(
        icon: PhosphorIconsRegular.checkCircle,
        tone: AppColors.success,
        bg: AppColors.tintGreen,
        title: paid ? 'Payment received' : 'Awaiting payment',
        sub: '$ownerName · ${payment.date}',
      ),
      ActivityEntry(
        icon: PhosphorIconsRegular.receipt,
        tone: AppColors.blueBright,
        bg: AppColors.tintBlue,
        title: 'Invoice ${payment.invId ?? '—'} issued',
        sub: 'System · on creation',
      ),
    ];
  }
}
