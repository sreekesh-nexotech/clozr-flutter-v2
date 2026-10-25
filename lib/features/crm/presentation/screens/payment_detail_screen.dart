import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/presentation/components/acc_widgets.dart';
import '../../../accounting/presentation/sheets/acc_sheet_scaffold.dart' show confirmAcc;
import '../../../auth/application/providers/module_perm_providers.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/payment_plan/payment_plan_detail.dart';
import '../../application/payment_plan/payment_plan_rules.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/payment_plan_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../components/finance_widgets.dart';
import '../components/payment_plan/plan_widgets.dart';

/// One payment record (webapp `PaymentDetailScreen`): the amount due incl.
/// GST, status, method and dates; the plan it belongs to; the accounting card
/// while accounting is active; a synthetic activity; local-only notes.
///
/// Read-only like the web — no edit or mark-unpaid. The one action is Delete
/// (PY-011), offered only for an unpaid, uninvoiced record on a milestone-type
/// plan to a user with payment delete.
class PaymentDetailScreen extends ConsumerStatefulWidget {
  const PaymentDetailScreen({super.key});

  @override
  ConsumerState<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentDetailScreenState extends ConsumerState<PaymentDetailScreen> {
  /// Local-only notes — the web keeps them in page state too (no notes API
  /// for a payment record).
  final List<NoteEntry> _notes = [];
  bool _deleting = false;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.payments);
    }
  }

  Widget _scaffold(Widget child) => Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Payment', onBack: () => context.pop()),
            Expanded(child: child),
          ],
        ),
      );

  Widget _errorState(Object e) {
    final notFound = e is AppError && e.type == AppErrorType.notFound;
    return EmptyState(
      icon: notFound ? PhosphorIconsRegular.wallet : PhosphorIconsRegular.warning,
      iconColor: notFound ? AppColors.textPlaceholder : AppColors.error,
      title: notFound ? 'Payment not found' : "Couldn't load this payment",
      body: notFound
          ? 'This payment may have been deleted.'
          : (e is AppError ? e.message : 'Something went wrong. Please try again.'),
      ctaLabel: 'Back to payments',
      onCta: _back,
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    if (id.isEmpty) {
      return _scaffold(_errorState(const AppError(type: AppErrorType.notFound, message: '')));
    }
    final async = ref.watch(paymentRecordDetailProvider(id));
    final record = async.valueOrNull;
    if (record == null) {
      if (async.hasError) return _scaffold(_errorState(async.error!));
      return _scaffold(const DetailSkeleton());
    }
    return _content(record);
  }

  Future<void> _refresh(PlanRecord r) async {
    ref.invalidate(paymentRecordDetailProvider(r.id));
    if (r.planId.isNotEmpty) ref.invalidate(paymentPlanDetailProvider(r.planId));
    try {
      await ref.read(paymentRecordDetailProvider(r.id).future);
    } catch (_) {
      // Rendered by the page's own error state.
    }
  }

  Future<void> _delete(PlanRecord r) async {
    if (_deleting || !ensurePermission(ref, 'payment', PermVerb.delete)) return;
    final ok = await confirmAcc(
      context,
      title: deleteRecordTitle,
      body: deleteRecordBody,
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(paymentPlanRemoteProvider).deleteRecord(r.id);
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      ref.read(toastProvider.notifier).showError(e.bareMessage);
      if (mounted) setState(() => _deleting = false);
      return;
    }
    ref.read(toastProvider.notifier).show('Payment record deleted');
    // The server recalculates the plan's totals.
    if (r.planId.isNotEmpty) ref.invalidate(paymentPlanDetailProvider(r.planId));
    ref.invalidate(invoicesProvider);
    ref.invalidate(paymentsProvider);
    if (mounted) _back();
  }

  Widget _content(PlanRecord r) {
    final plan = r.planId.isEmpty ? null : ref.watch(paymentPlanDetailProvider(r.planId)).valueOrNull;
    final meta = recordStatusMeta(r);
    final canDelete = plan != null &&
        canDeleteRecord(planType: plan.ptype, record: r, canDelete: ref.watch(modulePermProvider('payment')).delete);
    final accounting = ref.watch(accountingActiveProvider);

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Payment',
            name: r.displayLabel,
            onBack: () => context.pop(),
            trailing: canDelete
                ? DetailIconAction(icon: PhosphorIconsRegular.trash, onTap: () => _delete(r))
                : null,
          ),
          Expanded(
            child: AppRefresh(
              onRefresh: () => _refresh(r),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
                children: [
                  _headerCard(r, meta),
                  SizedBox(height: 14.h),
                  _relatedCard(r, plan),
                  SizedBox(height: 14.h),
                  _infoCard(r, meta, plan),
                  SizedBox(height: 14.h),
                  if (accounting) ...[
                    _accountingCard(r),
                    SizedBox(height: 14.h),
                  ],
                  FinanceCard(
                    title: 'Activity',
                    child: Padding(
                      padding: EdgeInsets.only(top: 6.h),
                      child: ActivityTimeline(entries: _activity(r)),
                    ),
                  ),
                  SizedBox(height: 14.h),
                  NotesCard(
                    notes: List.of(_notes),
                    countLabel: '${_notes.length}',
                    onSend: (body) => setState(() => _notes.insert(
                        0, NoteEntry(initials: 'Y', author: 'You', time: 'Just now', body: body))),
                  ),
                  if (_notes.isEmpty) ...[
                    SizedBox(height: 8.h),
                    const Center(child: PlanHint('No notes yet — add the first one above.')),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(PlanRecord r, StatusMeta meta) {
    final who = r.customerName.isNotEmpty ? r.customerName : r.leadName;
    final plan = r.quoteNumber.isNotEmpty ? r.quoteNumber : 'Payment plan';
    final hint = amountDueHint(r);
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconChip(icon: planMethodIcon(r.method)),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.displayLabel,
                        style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                    if (who.isNotEmpty || r.productName.isNotEmpty) ...[
                      SizedBox(height: 3.h),
                      Text([if (who.isNotEmpty) who, if (r.productName.isNotEmpty) r.productName].join(' · '),
                          style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                    SizedBox(height: 3.h),
                    Text('$plan · ${recordRowDate(r)}',
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AMOUNT DUE (INCL. GST)',
                        style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
                    SizedBox(height: 3.h),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(planMoney(r.amountDueInclGst),
                          style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.navy, letterSpacing: -0.4)),
                    ),
                    if (hint.isNotEmpty)
                      Text(hint, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                    if (hasGstOnTop(r))
                      Text('As quoted ${planMoney(r.amountExpected)}',
                          style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('STATUS',
                      style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
                  SizedBox(height: 6.h),
                  StatusPill.meta(meta),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _relatedCard(PlanRecord r, PlanDetail? plan) {
    final chips = <Widget>[
      if (r.planId.isNotEmpty)
        _relChip(
          kind: 'Payment plan',
          name: r.quoteNumber.isNotEmpty ? r.quoteNumber : '—',
          onTap: () => context.push('${Routes.invoiceDetail}?id=${r.planId}'),
        ),
      if (plan != null && plan.customerId.isNotEmpty)
        _relChip(
          kind: 'Customer',
          name: plan.customerName.isNotEmpty ? plan.customerName : 'Customer',
          onTap: () => context.push('${Routes.customerDetail}?id=${plan.customerId}'),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return FinanceCard(
      title: 'Related',
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
                  Text(kind.toUpperCase(),
                      style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
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

  Widget _infoCard(PlanRecord r, StatusMeta meta, PlanDetail? plan) {
    final method = paymentMethodLabel(r.method);
    final rows = <(String, String)>[
      ('Amount due (incl. GST)', '${planMoney(r.amountDueInclGst)}${amountDueHint(r).isEmpty ? '' : ' ${amountDueHint(r)}'}'),
      if (hasGstOnTop(r)) ('Amount as quoted', planMoney(r.amountExpected)),
      ('Balance due', planMoney(r.balanceDue)),
      ('Status', meta.label),
      ('Method', method.isEmpty ? '—' : method),
      ('Installment', r.installmentNumber > 0 ? '#${r.installmentNumber}' : '—'),
      ('Date', recordRowDate(r)),
      ('Payment plan', r.quoteNumber.isNotEmpty ? r.quoteNumber : (r.planId.isNotEmpty ? r.planId : '—')),
      if (plan != null && plan.ownerName.isNotEmpty)
        ('Collection owner', plan.ownerEmail.isNotEmpty ? '${plan.ownerName} · ${plan.ownerEmail}' : plan.ownerName),
    ];
    return FinanceCard(
      title: 'Payment information',
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++)
            MetaRow(label: rows[i].$1, value: rows[i].$2, last: i == rows.length - 1),
        ],
      ),
    );
  }

  /// How the record sits in the books (accounting active only).
  Widget _accountingCard(PlanRecord r) {
    final doc = r.document;
    final receipt = r.receipt;
    String money(double v) => v > 0 ? formatMoneyStr(v) : '—';
    final servicePeriod = r.servicePeriodStart.isNotEmpty && r.servicePeriodEnd.isNotEmpty
        ? '${planDate(r.servicePeriodStart)} → ${planDate(r.servicePeriodEnd)}'
        : '';
    final docStatus = const {'DRAFT': 'Draft', 'ISSUED': 'Issued', 'CANCELLED': 'Cancelled', 'VOID_DRAFT': 'Void'};
    final rows = <(String, String)>[
      if (doc != null && doc.status == 'ISSUED')
        ('Invoice open balance', '${formatMoneyStr(doc.openBalance)} of ${formatMoneyStr(doc.grandTotal)}'),
      (
        'Receipt',
        receipt == null
            ? 'Not posted'
            : '${formatMoneyStr(receipt.amount)}${receipt.kind.isNotEmpty ? ' · ${receipt.kind}' : ''}'
                '${receipt.status.isNotEmpty ? ' · ${humanizeEnum(receipt.status)}' : ''}',
      ),
      if (r.amountCredited > 0) ('Credited', formatMoneyStr(r.amountCredited)),
      if (r.amountRefunded > 0)
        ('Refunded', '${formatMoneyStr(r.amountRefunded)}${r.amountRefundNotDue > 0 ? ' · deal closed, not due again' : ''}'),
      if (r.cancelReason.isNotEmpty) ('Cancelled', r.cancelReason),
      ('TDS deducted', money(r.tds)),
      ('Bank charge', money(r.bankCharge)),
      if (r.gstTds > 0 || r.gstTcs > 0) ('GST TDS / TCS', '${formatMoneyStr(r.gstTds)} / ${formatMoneyStr(r.gstTcs)}'),
      ('Bank / gateway ref', r.gatewayRef.isNotEmpty ? r.gatewayRef : '—'),
      if (r.treatAs.isNotEmpty) ('Treated as', treatAsLabels[r.treatAs] ?? humanizeEnum(r.treatAs)),
      if (servicePeriod.isNotEmpty) ('Service period', servicePeriod),
    ];
    return FinanceCard(
      title: 'Accounting',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tax invoice: tappable when there is one.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: doc == null ? null : () => context.push('${Routes.accDocumentDetail}?id=${doc.id}'),
            child: MetaRow(
              label: 'Tax invoice',
              value: doc == null
                  ? 'Not invoiced yet'
                  : '${doc.number.isNotEmpty ? doc.number : 'Draft'} · ${docStatus[doc.status] ?? humanizeEnum(doc.status)}'
                      '${doc.status == 'ISSUED' && doc.paymentState.isNotEmpty && doc.paymentState != 'NA' ? ' · ${humanizeEnum(doc.paymentState)}' : ''}',
            ),
          ),
          for (int i = 0; i < rows.length; i++)
            MetaRow(label: rows[i].$1, value: rows[i].$2, last: i == rows.length - 1),
          if (r.status == 'paid') ...[
            SizedBox(height: 10.h),
            const AccInfoBanner(
              'Changing the amount, TDS or date of this paid payment reverses its receipt and posts a new one. '
              'Marking it unpaid reverses the receipt.',
              icon: PhosphorIconsRegular.warning,
            ),
          ],
        ],
      ),
    );
  }

  List<ActivityEntry> _activity(PlanRecord r) {
    final items = recordActivity(r);
    final paid = r.status == 'paid';
    return [
      ActivityEntry(
        icon: paid ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.clock,
        tone: paid ? AppColors.success : AppColors.warning,
        bg: paid ? AppColors.tintGreen : AppColors.tintAmber,
        title: items[0].$1,
        sub: items[0].$2,
      ),
      ActivityEntry(
        icon: PhosphorIconsRegular.fileText,
        tone: AppColors.blueBright,
        bg: AppColors.tintBlue,
        title: items[1].$1,
        sub: items[1].$2,
      ),
    ];
  }
}
