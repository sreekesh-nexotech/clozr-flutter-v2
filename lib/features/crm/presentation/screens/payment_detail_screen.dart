import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../../domain/entities/payment.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../components/crm_async.dart';
import '../components/finance_widgets.dart';

/// Payment detail — header (amount + status + optional "Mark as paid"), related
/// links, payment detail rows, activity and notes.
class PaymentDetailScreen extends ConsumerWidget {
  const PaymentDetailScreen({super.key});

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
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headerCard(ref, payment, meta, canMarkPaid),
                SizedBox(height: 14.h),
                _relatedCard(context, payment, cust, linkedInvoice?.quoteId),
                SizedBox(height: 14.h),
                _detailsCard(payment, meta, owner),
                SizedBox(height: 14.h),
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
        ],
      ),
    );
  }

  Widget _headerCard(WidgetRef ref, Payment payment, StatusMeta meta, bool canMarkPaid) {
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
              onTap: () => ref.read(toastProvider.notifier).show('Payment marked as paid'),
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
          MetaRow(label: 'Amount', value: payment.amount),
          MetaRow(label: 'Status', value: meta.label),
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
