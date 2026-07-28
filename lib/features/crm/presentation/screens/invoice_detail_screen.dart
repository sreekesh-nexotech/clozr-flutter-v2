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
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/payment.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../components/finance_widgets.dart';

/// Invoice detail — header (id + status, total/paid/balance, action buttons) and
/// the installment schedule (tappable payment rows), plus notes.
class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final invoice = ref.watch(invoiceByIdProvider(id));

    if (invoice == null) {
      return Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Invoice', onBack: () => context.pop()),
            const Expanded(child: Center(child: Text('Invoice not found'))),
          ],
        ),
      );
    }

    final meta = StatusMeta$.invoice[invoice.status] ?? StatusMeta$.invoice['partial']!;
    final cust = CrmPartyDirectory.customer(invoice.custId);
    final schedule = ref.watch(paymentsForInvoiceProvider(invoice.id));
    final paidNum = schedule.where((p) => p.status == 'paid').fold<int>(0, (a, b) => a + b.amountNum);

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Invoice',
            name: invoiceWho(invoice),
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => ref.read(toastProvider.notifier).show('Invoice actions'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headerCard(context, ref, invoice, meta, cust, paidNum),
                SizedBox(height: 14.h),
                FinanceCard(
                  title: 'Installment schedule',
                  child: Column(
                    children: [
                      for (int i = 0; i < schedule.length; i++)
                        _scheduleRow(context, ref, schedule[i], last: i == schedule.length - 1),
                    ],
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

  Widget _headerCard(BuildContext context, WidgetRef ref, Invoice invoice, StatusMeta meta, CrmParty? cust, int paidNum) {
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconChip(icon: PhosphorIconsRegular.receipt, size: 46, radius: 13, iconSize: 22),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(invoice.id,
                            style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        SizedBox(width: 8.w),
                        StatusPill.meta(meta),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text('${cust?.company ?? invoice.custId ?? '—'} · ${cust?.name ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 3.h),
                    Text('${invoice.type} · ${invoice.settled} of ${invoice.of} settled',
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              _stat('TOTAL', invoice.total, AppColors.textPrimary),
              _stat('PAID', paidNum == 0 ? '₹0L' : _fmtAmt(paidNum), AppColors.success),
              _stat('BALANCE', invoice.balance, AppColors.error),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              Expanded(
                child: _ghostButton(
                  icon: PhosphorIconsRegular.buildings,
                  label: 'Customer',
                  onTap: () {
                    if (cust != null) context.push('${Routes.customerDetail}?id=${cust.id}');
                  },
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _ghostButton(
                  icon: PhosphorIconsRegular.fileText,
                  label: '#${invoice.quoteId ?? '—'}',
                  onTap: () {
                    if (invoice.quoteId != null) {
                      context.push('${Routes.quoteDetail}?id=${invoice.quoteId}');
                    } else {
                      ref.read(toastProvider.notifier).show('Quote not found');
                    }
                  },
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                flex: 12,
                child: GestureDetector(
                  onTap: () => ref.read(toastProvider.notifier).show('Record payment'),
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.plus, size: 14.sp, color: AppColors.white),
                        SizedBox(width: 7.w),
                        Text('Record payment',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
          SizedBox(height: 3.h),
          Text(value, style: AppText.custom(size: 17, weight: FontWeight.w800, color: valueColor)),
        ],
      ),
    );
  }

  Widget _ghostButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: const Color(0xFFE6E7EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16.sp, color: AppColors.textSecondary),
            SizedBox(width: 7.w),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBody)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleRow(BuildContext context, WidgetRef ref, Payment p, {required bool last}) {
    final meta = StatusMeta$.payment[p.status] ?? StatusMeta$.payment['due']!;
    final methodLabel = p.method == '—' ? 'Not set' : p.method;
    final canPay = p.status != 'paid';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.paymentDetail}?id=${p.id}'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconChip(icon: payMethodIcon(p.method), iconSize: 18),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.label, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text('${p.id} · $methodLabel', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  SizedBox(height: 2.h),
                  Text(p.date, style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: paymentDateColor(p.status))),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(p.amount, style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                SizedBox(height: 5.h),
                StatusPill.meta(meta),
                if (canPay) ...[
                  SizedBox(height: 5.h),
                  GestureDetector(
                    onTap: () => ref.read(toastProvider.notifier).show('Installment settled'),
                    child: Text('Settle now',
                        style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.blueBright)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The prototype's `fmtAmt` for the paid total (Cr above ₹1Cr, else L).
  String _fmtAmt(int x) {
    if (x >= 10000000) {
      return '₹${_trim((x / 100000).round() / 100)}Cr';
    }
    return '₹${_trim((x / 10000).round() / 10)}L';
  }

  String _trim(num v) {
    var s = v.toString();
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }
}
