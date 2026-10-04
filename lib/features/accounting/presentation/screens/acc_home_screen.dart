import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../../application/providers/reports_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../../domain/entities/acc_ledger.dart';
import '../../domain/entities/acc_periods.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';
import '../sheets/record_expense_sheet.dart';
import '../sheets/record_receipt_sheet.dart';
import '../sheets/vendor_payment_sheet.dart';

/// Accounting home (plan §4.1) — who owes what, what is owed, TDS pending and
/// drafts waiting; then what needs attention and the four field actions.
///
/// Each tile shows only for a role that can read its source, and says "—"
/// rather than zero while it loads or when the read fails — a ledger figure
/// that is wrong is worse than one that is missing.
class AccHomeScreen extends ConsumerWidget {
  const AccHomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(accountingStatusProvider);
    ref.invalidate(arAgingProvider);
    ref.invalidate(apAgingProvider);
    ref.invalidate(draftInvoicesProvider);
    ref.invalidate(rejectedEventsProvider);
    ref.invalidate(periodRegisterProvider);
    ref.invalidate(tdsSummaryProvider);
    await settle([ref.read(accountingStatusProvider.future)]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canInvoice = ref.watch(accPermProvider('acc_document')).create;
    registerAdd(
      ref,
      canInvoice ? AddAction(label: 'New invoice', run: (ctx) => ctx.push(Routes.accNewInvoice)) : null,
    );
    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 16.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Accounting', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                      SizedBox(height: 1.h),
                      Text('Overview', style: AppText.screenTitle()),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: 3.h),
                  child: Text(DateFormat('EEE, d MMM').format(DateTime.now()),
                      style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ),
              ],
            ),
            SizedBox(height: 12.h),
          ],
        ),
        Expanded(
          child: AppRefresh(
            onRefresh: () => _refresh(ref),
            child: AccountingGate(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                children: [
                  _kpis(context, ref),
                  SizedBox(height: 16.h),
                  _actions(context, ref),
                  SizedBox(height: 16.h),
                  _attention(context, ref),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpis(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(accPermProvider('acc_report')).read;
    final docs = ref.watch(accPermProvider('acc_document')).read;
    final ar = reports ? ref.watch(arAgingProvider).valueOrNull : null;
    final ap = reports ? ref.watch(apAgingProvider).valueOrNull : null;
    final drafts = docs ? ref.watch(draftInvoicesProvider).valueOrNull : null;
    final tds = reports ? _tdsPending(ref) : null;

    final cards = <Widget>[
      if (reports)
        KpiCard(
          icon: PhosphorIconsFill.arrowCircleDown,
          iconColor: AppColors.blueBright,
          iconBg: AppColors.tintBlue,
          value: ar == null ? '—' : formatMoneyCompact(ar.grandTotal),
          label: 'Receivable',
          sub: ar == null ? 'Owed to you' : '90+ days ${formatMoneyCompact(ar.totals['90+'])}',
          accent: AppColors.blueBright,
          onTap: () => context.push('${Routes.accReport}?kind=ar_aging'),
        ),
      if (reports)
        KpiCard(
          icon: PhosphorIconsFill.arrowCircleUp,
          iconColor: AppColors.warningDeep,
          iconBg: AppColors.tintAmber,
          value: ap == null ? '—' : formatMoneyCompact(ap.grandTotal),
          label: 'Payable',
          sub: 'You owe vendors',
          accent: AppColors.warning,
          onTap: () => context.push('${Routes.accReport}?kind=ap_aging'),
        ),
      if (reports)
        KpiCard(
          icon: PhosphorIconsFill.percent,
          iconColor: AppColors.pending,
          iconBg: AppColors.tintPurple,
          value: tds == null ? '—' : formatMoneyCompact(tds),
          label: 'TDS to deposit',
          sub: 'This quarter',
          accent: AppColors.pending,
          onTap: () => context.push(Routes.accPeriods),
        ),
      if (docs)
        KpiCard(
          icon: PhosphorIconsFill.fileDashed,
          iconColor: AppColors.textMuted,
          iconBg: AppColors.tintGrey,
          value: drafts == null ? '—' : '${drafts.count}',
          label: 'Drafts',
          sub: 'Waiting to be issued',
          accent: AppColors.textMuted,
          onTap: () => context.go(Routes.accInvoices),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (int i = 0; i < cards.length; i += 2) {
      rows.add(Row(children: [
        Expanded(child: cards[i]),
        SizedBox(width: 12.w),
        Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox.shrink()),
      ]));
      if (i + 2 < cards.length) rows.add(SizedBox(height: 12.h));
    }
    return Column(children: rows);
  }

  /// TDS pending for the quarter covering today, from the period register.
  String? _tdsPending(WidgetRef ref) {
    if (!ref.watch(accPermProvider('acc_period')).read) return null;
    final reg = ref.watch(periodRegisterProvider).valueOrNull;
    if (reg == null) return null;
    final today = DateTime.now();
    TdsPeriod? current;
    for (final p in reg.tdsPeriods) {
      final s = DateTime.tryParse(p.startDate ?? '');
      final e = DateTime.tryParse(p.endDate ?? '');
      if (s != null && e != null && !today.isBefore(s) && !today.isAfter(e.add(const Duration(days: 1)))) current = p;
    }
    if (current == null) return null;
    return ref.watch(tdsSummaryProvider(current.id)).valueOrNull?.totals['pending'];
  }

  Widget _actions(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(accPermProvider('acc_document')).create;
    final settle = ref.watch(accPermProvider('acc_settlement')).create;
    final purchase = ref.watch(accPermProvider('acc_purchase')).create;
    final actions = <(IconData, String, VoidCallback)>[
      if (doc) (PhosphorIconsRegular.receipt, 'New invoice', () => context.push(Routes.accNewInvoice)),
      if (settle) (PhosphorIconsRegular.arrowDown, 'Record receipt', () => showRecordReceiptSheet(context)),
      if (purchase) (PhosphorIconsRegular.shoppingCart, 'Record expense', () => showRecordExpenseSheet(context)),
      if (settle) (PhosphorIconsRegular.arrowUp, 'Pay vendor', () => showVendorPaymentSheet(context)),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return ClozrCard(
      padding: EdgeInsets.fromLTRB(10.w, 14.h, 10.w, 12.h),
      child: Row(
        children: [
          for (final a in actions)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: a.$3,
                child: Column(
                  children: [
                    Container(
                      width: 44.w,
                      height: 44.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(13.r)),
                      child: Icon(a.$1, size: 20.sp, color: AppColors.navy),
                    ),
                    SizedBox(height: 7.h),
                    Text(a.$2,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _attention(BuildContext context, WidgetRef ref) {
    final items = <Widget>[];
    // Postings the ledger refused.
    if (ref.watch(accPermProvider('acc_journal')).read) {
      for (final e in ref.watch(rejectedEventsProvider).valueOrNull ?? const <LedgerEvent>[]) {
        items.add(_row(
          icon: PhosphorIconsFill.xCircle,
          tone: AppColors.error,
          title: 'Posting rejected · ${label(const {}, e.eventType)}',
          sub: e.error ?? 'The ledger refused this event.',
          trailing: AccPill(StatusMeta$.accEvent, e.status),
          onTap: () => _showEvent(context, e),
        ));
      }
    }
    // Drafts left for more than a week.
    if (ref.watch(accPermProvider('acc_document')).read) {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      for (final d in ref.watch(draftInvoicesProvider).valueOrNull?.results ?? const <AccDocument>[]) {
        final date = DateTime.tryParse(d.documentDate ?? '');
        if (date == null || date.isAfter(cutoff)) continue;
        items.add(_row(
          icon: PhosphorIconsFill.fileDashed,
          tone: AppColors.warningDeep,
          title: 'Draft from ${formatApiDay(d.documentDate)}',
          sub: 'Estimated ${formatMoneyStr(d.grandTotal)} — not issued yet',
          onTap: () => context.push('${Routes.accDocumentDetail}?id=${d.id}'),
        ));
      }
    }
    // GST periods that have ended but are not settled.
    if (ref.watch(accPermProvider('acc_period')).read) {
      final today = DateTime.now();
      for (final p in ref.watch(periodRegisterProvider).valueOrNull?.gstPeriods ?? const <GstPeriod>[]) {
        final end = DateTime.tryParse(p.endDate ?? '');
        if (end == null || !end.isBefore(today) || p.settled) continue;
        items.add(_row(
          icon: PhosphorIconsFill.calendarX,
          tone: AppColors.pending,
          title: 'GST ${formatApiDay(p.startDate)} – ${formatApiDay(p.endDate)} not settled',
          sub: 'GSTR-1 ${label(const {}, p.gstr1Status)} · GSTR-3B ${label(const {}, p.gstr3bStatus)}',
          onTap: () => context.push(Routes.accPeriods),
        ));
      }
    }
    return ClozrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Needs attention', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('Rejected postings, old drafts and open GST periods',
              style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 22.h, bottom: 10.h),
              child: Center(
                child: Text('Nothing needs attention right now.',
                    style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ),
            )
          else
            ...items,
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color tone,
    required String title,
    required String sub,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18.sp, color: tone),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                ],
              ),
            ),
            if (trailing != null) ...[SizedBox(width: 8.w), trailing],
          ],
        ),
      ),
    );
  }

  void _showEvent(BuildContext context, LedgerEvent e) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(label(const {}, e.eventType), style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
        content: Text(
          [
            e.error ?? 'No reason was recorded.',
            if (e.receivedAt != null) 'Received ${formatApiDay(e.receivedAt!.split('T').first)}',
            'Ask your accountant to review it on the web app.',
          ].join('\n\n'),
          style: AppText.body(color: AppColors.textMuted).copyWith(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: AppText.bodyStrong(color: AppColors.navy)),
          ),
        ],
      ),
    );
  }
}
