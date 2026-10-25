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
import '../../../../core/widgets/list_skeleton.dart';
// Prefixed: `finance_widgets` exports its own, lighter `NoteEntry` for the card.
import '../../../../core/models/note.dart' as notes_model;
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/api/roster.dart';
import '../../../auth/application/providers/module_perm_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/payment_plan/payment_plan_detail.dart';
import '../../application/payment_plan/payment_plan_rules.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/lead_lifecycle_providers.dart';
import '../../application/providers/payment_plan_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../components/finance_widgets.dart';
import '../components/lead_lifecycle_sheets.dart' show showCustomerMatchSheet;
import '../components/payment_plan/add_milestone_sheet.dart';
import '../components/payment_plan/plan_schedule_card.dart';
import '../components/payment_plan/plan_widgets.dart';
import '../components/payment_plan/recurring_schedule_card.dart';
import '../components/record_payment_sheet.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/presentation/components/acc_widgets.dart';
import '../../../accounting/presentation/components/plan_billing_card.dart';
import '../../../accounting/presentation/sheets/invoice_from_record_sheet.dart';
import '../../../auth/presentation/components/permission_guard.dart';

/// Payment plan detail (webapp `InvoiceDetailScreen`): header with the type
/// label, progress and incl.-GST KPIs; needs-attention; recurring schedule;
/// the "Instalments" re-split card; the instalment / milestone schedule with
/// per-row "Settle"; the collection owner; notes.
///
/// The route's `id` may be the plan's `payment_id` or its display id (the
/// quote number) — the latter is resolved through the plan list. The page
/// itself always reads `GET /quotations/payments/{payment_id}/`.
class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = GoRouterState.of(context).uri.queryParameters;
    final raw = (params['uuid'] ?? '').isNotEmpty ? params['uuid']! : (params['id'] ?? '');

    Widget scaffold(Widget child) => Container(
          color: AppColors.bgDetail,
          child: Column(
            children: [
              DetailAppBar(section: 'Payment plan', onBack: () => context.pop()),
              Expanded(child: child),
            ],
          ),
        );

    if (raw.isEmpty) return scaffold(_notFound(context));
    if (isUuidLike(raw)) return _PlanBody(planId: raw, scaffold: scaffold);

    // A display id: find its plan in the list first.
    final list = ref.watch(invoicesProvider);
    return list.when(
      loading: () => scaffold(const DetailSkeleton()),
      error: (e, _) => scaffold(_loadError(context, ref, e, () => ref.invalidate(invoicesProvider))),
      data: (_) {
        final iv = ref.watch(invoiceByIdProvider(raw));
        if (iv == null || iv.uuid.isEmpty) return scaffold(_notFound(context));
        return _PlanBody(planId: iv.uuid, scaffold: scaffold);
      },
    );
  }
}

void _backToPlans(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.payments);
  }
}

Widget _notFound(BuildContext context) => EmptyState(
      icon: PhosphorIconsRegular.fileText,
      title: 'Payment plan not found',
      body: 'This payment plan may have been deleted.',
      ctaLabel: 'Back to payment plans',
      onCta: () => _backToPlans(context),
    );

Widget _loadError(BuildContext context, WidgetRef ref, Object e, VoidCallback retry) {
  if (e is AppError && e.type == AppErrorType.notFound) return _notFound(context);
  return EmptyState(
    icon: PhosphorIconsRegular.warning,
    iconColor: AppColors.error,
    title: "Couldn't load this payment plan",
    body: e is AppError ? e.message : 'Something went wrong. Please try again.',
    ctaLabel: 'Back to payment plans',
    onCta: () => _backToPlans(context),
  );
}

class _PlanBody extends ConsumerStatefulWidget {
  const _PlanBody({required this.planId, required this.scaffold});

  final String planId;
  final Widget Function(Widget) scaffold;

  @override
  ConsumerState<_PlanBody> createState() => _PlanBodyState();
}

class _PlanBodyState extends ConsumerState<_PlanBody> {
  bool _converting = false;

  Future<void> _refresh() async {
    ref.invalidate(paymentPlanDetailProvider(widget.planId));
    ref.invalidate(invoicesProvider);
    ref.invalidate(paymentsProvider);
    // Whole family: the notes notifier loads in its constructor.
    ref.invalidate(crmNotesProvider);
    try {
      await ref.read(paymentPlanDetailProvider(widget.planId).future);
    } catch (_) {
      // The page renders its own error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(paymentPlanDetailProvider(widget.planId));
    // Keep showing the last plan while a write-tick refetch runs.
    final plan = async.valueOrNull;
    if (plan == null) {
      if (async.hasError) {
        return widget.scaffold(_loadError(context, ref, async.error!,
            () => ref.invalidate(paymentPlanDetailProvider(widget.planId))));
      }
      return widget.scaffold(const DetailSkeleton());
    }
    return _content(context, plan);
  }

  // ── Permissions / derived ──

  ModulePerm get _perm => ref.watch(modulePermProvider('payment'));

  String _leadId(PlanDetail p) {
    if (p.leadId.isNotEmpty) return p.leadId;
    if (p.customerId.isNotEmpty) return '';
    return ref.watch(planQuoteLeadIdProvider(p.quotationUuid)).valueOrNull ?? '';
  }

  Widget _content(BuildContext context, PlanDetail p) {
    final accounting = ref.watch(accountingActiveProvider);
    final perm = _perm;
    final canRecord = canRecordPayment(p, canCreate: perm.create);
    final milestones = canAddMilestones(p) && perm.update;
    final attention = effectiveNeedsAttention(p);
    final leadId = _leadId(p);
    // The billing card (PY-030, on hold) still reads the list entity.
    final listInvoice = accounting
        ? (ref.watch(invoicesProvider).valueOrNull ?? const []).where((i) => i.uuid == p.id).firstOrNull
        : null;

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Payment plan',
            name: p.quoteNumber.isNotEmpty ? p.quoteNumber : null,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: AppRefresh(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
                children: [
                  _headerCard(context, p, accounting: accounting, canRecord: canRecord, milestones: milestones, leadId: leadId),
                  SizedBox(height: 14.h),
                  if (attention.isNotEmpty) ...[
                    _attentionBanner(context, p, attention, milestones: milestones, leadId: leadId),
                    SizedBox(height: 14.h),
                  ],
                  if (listInvoice != null) ...[
                    PlanBillingCard(invoice: listInvoice),
                    SizedBox(height: 14.h),
                  ],
                  if (p.recurring != null) ...[
                    RecurringScheduleCard(
                      key: ValueKey('${p.id}:${p.recurring!.stopFrom}'),
                      plan: p,
                      canEdit: perm.update,
                    ),
                    SizedBox(height: 14.h),
                  ],
                  if (canChooseInstalments(p)) ...[
                    PlanScheduleCard(
                      key: ValueKey('${p.id}:${p.records.length}:${p.ptype}'),
                      plan: p,
                      canEdit: perm.update,
                    ),
                    SizedBox(height: 14.h),
                  ],
                  _scheduleCard(context, p, attention, accounting: accounting, canRecord: canRecord),
                  SizedBox(height: 14.h),
                  _notesCard(p),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──

  Widget _headerCard(
    BuildContext context,
    PlanDetail p, {
    required bool accounting,
    required bool canRecord,
    required bool milestones,
    required String leadId,
  }) {
    final meta = planStatusMeta(planStatusKey(p));
    final kpis = planKpis(p, accountingActive: accounting);
    final adjustments = adjustmentLines(credited: p.amountCredited, refunded: p.amountRefunded);
    final split = chargeSplitLink(p);
    final leadName = p.records.map((r) => r.leadName).firstWhere((n) => n.isNotEmpty, orElse: () => '');
    final who = p.customerName.isNotEmpty ? p.customerName : leadName;

    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconChip(icon: PhosphorIconsRegular.fileText, size: 46, radius: 13, iconSize: 22),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 4.h,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(p.quoteNumber.isNotEmpty ? p.quoteNumber : 'Payment plan',
                            style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        StatusPill.meta(meta),
                      ],
                    ),
                    if (who.isNotEmpty) ...[
                      SizedBox(height: 3.h),
                      Row(
                        children: [
                          Flexible(
                            child: Text(who,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                          ),
                          if (p.customerId.isEmpty) ...[SizedBox(width: 6.w), const _LeadBadge()],
                        ],
                      ),
                    ],
                    SizedBox(height: 3.h),
                    Text('${planHeaderType(p)} · ${planProgressLabel(p)}',
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                    if (p.chargeSplit != null && p.chargeSplit!.label.isNotEmpty) ...[
                      SizedBox(height: 4.h),
                      Text(p.chargeSplit!.label,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                      if (split != null) ...[
                        SizedBox(height: 2.h),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context.push('${Routes.invoiceDetail}?id=${split.$1}'),
                          child: Text(split.$2,
                              style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.blueBright)
                                  .copyWith(decoration: TextDecoration.underline, decorationColor: AppColors.blueBright)),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          _kpiGrid(kpis),
          if (adjustments.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text('ADJUSTMENTS', style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
            for (final line in adjustments)
              Text(line, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
          ],
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          _actions(context, p, canRecord: canRecord, milestones: milestones, leadId: leadId),
        ],
      ),
    );
  }

  /// Three KPIs in a row; four (accounting) as a 2 × 2 grid.
  Widget _kpiGrid(List<PlanKpi> kpis) {
    Widget cell(PlanKpi k) => Expanded(child: _kpi(k));
    if (kpis.length <= 3) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final k in kpis) cell(k)]);
    return Column(
      children: [
        for (var i = 0; i < kpis.length; i += 2) ...[
          if (i > 0) SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [cell(kpis[i]), if (i + 1 < kpis.length) cell(kpis[i + 1]) else const Spacer()],
          ),
        ],
      ],
    );
  }

  Widget _kpi(PlanKpi k) {
    final color = switch (k.tone) {
      'success' => AppColors.success,
      'navy' => AppColors.navy,
      'muted' => AppColors.textSecondary,
      _ => AppColors.textPrimary,
    };
    return Padding(
      padding: EdgeInsets.only(right: 8.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k.label.toUpperCase(),
              style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.3)),
          SizedBox(height: 3.h),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(planMoney(k.value), style: AppText.custom(size: 16, weight: FontWeight.w800, color: color)),
          ),
          if (k.sub != null) ...[
            SizedBox(height: 2.h),
            Text(k.sub!, maxLines: 2, style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
          ],
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, PlanDetail p,
      {required bool canRecord, required bool milestones, required String leadId}) {
    final party = p.customerId.isNotEmpty
        ? _ghostButton(
            icon: PhosphorIconsRegular.buildings,
            label: 'Customer',
            onTap: () => context.push('${Routes.customerDetail}?id=${p.customerId}'),
          )
        : leadId.isNotEmpty
            ? _ghostButton(
                icon: PhosphorIconsRegular.path,
                label: 'Lead',
                onTap: () => context.push('${Routes.leadDetail}?id=$leadId'),
              )
            : null;
    final quote = p.quotationUuid.isEmpty
        ? null
        : _ghostButton(
            icon: PhosphorIconsRegular.fileText,
            label: p.quoteNumber.isNotEmpty ? '#${p.quoteNumber}' : 'Quote',
            onTap: () => context.push('${Routes.quoteDetail}?id=${p.quoteNumber.isNotEmpty ? p.quoteNumber : p.quotationUuid}'),
          );
    return Column(
      children: [
        Row(
          children: [
            if (party != null) Expanded(flex: 9, child: party),
            if (party != null && (quote != null || canRecord)) SizedBox(width: 10.w),
            if (quote != null) Expanded(flex: 9, child: quote),
            if (quote != null && canRecord) SizedBox(width: 10.w),
            if (canRecord)
              Expanded(
                flex: 14,
                child: PlanButton(
                  label: 'Record payment',
                  icon: PhosphorIconsBold.plus,
                  filled: true,
                  height: 44,
                  onTap: () => _openRecordSheet(context, p),
                ),
              ),
          ],
        ),
        if (milestones) ...[
          SizedBox(height: 10.h),
          SizedBox(
            width: double.infinity,
            child: PlanButton(
              label: 'Add milestone',
              icon: PhosphorIconsRegular.flag,
              height: 44,
              onTap: () => showAddMilestoneSheet(context, p),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ghostButton({required IconData icon, required String label, required VoidCallback onTap}) =>
      PlanButton(label: label, icon: icon, color: AppColors.textBody, height: 44, onTap: onTap);

  Future<void> _openRecordSheet(BuildContext context, PlanDetail p, {String? recordId}) async {
    if (!ensurePermission(ref, 'payment', PermVerb.create)) return;
    final ok = await showRecordPaymentSheet(context, planId: p.id, recordId: recordId, lockPlan: true);
    if (ok && mounted) ref.invalidate(paymentPlanDetailProvider(p.id));
  }

  // ── Needs attention ──

  Widget _attentionBanner(BuildContext context, PlanDetail p, List<PlanAttention> items,
      {required bool milestones, required String leadId}) {
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: AppColors.tintAmber,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.warning.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsFill.warning, size: 15.sp, color: AppColors.warningDeep),
              SizedBox(width: 7.w),
              Text('Needs attention', style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          for (final a in items) ...[
            SizedBox(height: 10.h),
            Text(attentionText(a),
                style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textSecondary, height: 1.45)),
            if (a.code == milestonesRequired && milestones) ...[
              SizedBox(height: 8.h),
              PlanButton(
                label: 'Add milestone',
                icon: PhosphorIconsRegular.flag,
                filled: true,
                height: 36,
                onTap: () => showAddMilestoneSheet(context, p),
              ),
            ],
            if (a.code == customerRequired && leadId.isNotEmpty) ...[
              SizedBox(height: 8.h),
              PlanButton(
                label: _converting ? 'Converting…' : 'Convert lead to customer',
                icon: PhosphorIconsRegular.userCheck,
                filled: true,
                height: 36,
                busy: _converting,
                onTap: () => _convert(p, leadId),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// The webapp's "Convert lead to customer": the same conversion the lead
  /// detail runs (a `CUSTOMER_MATCH` asks which customer), then the plan is
  /// refetched so the customer link and the blocked rows refresh.
  Future<void> _convert(PlanDetail p, String leadId) async {
    if (_converting) return;
    final toast = ref.read(toastProvider.notifier);
    setState(() => _converting = true);
    Map<String, dynamic> body = const {};
    try {
      while (true) {
        ConvertResult result;
        try {
          result = await convertLead(ref, leadId, body);
        } on AppError catch (e) {
          ref.read(apiServiceProvider).handled(e);
          toast.showError(e.message);
          return;
        }
        if (!mounted) return;
        switch (result) {
          case NeedsCustomerChoice(:final match):
            final choice = await showCustomerMatchSheet(context, match);
            if (choice == null || !mounted) return;
            body = choice;
            continue;
          case ConversionRequested():
            toast.show('Conversion requested — waiting for approval');
          case Converted(:final customerName):
            toast.show('Converted to customer${customerName.isNotEmpty ? ' — $customerName' : ''}');
        }
        break;
      }
      ref.invalidate(paymentPlanDetailProvider(p.id));
      ref.invalidate(invoicesProvider);
      ref.invalidate(paymentsProvider);
      ref.invalidate(customersScopedProvider);
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  // ── Schedule ──

  Widget _scheduleCard(BuildContext context, PlanDetail p, List<PlanAttention> attention,
      {required bool accounting, required bool canRecord}) {
    final isMilestone = p.ptype == 'installment_custom';
    final unscheduled = p.unscheduledInclGst;
    return FinanceCard(
      title: isMilestone ? 'Milestones' : 'Installment schedule',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.records.isNotEmpty && unscheduled != null && unscheduled > 0.005)
            Padding(
              padding: EdgeInsets.only(bottom: 4.h),
              child: Text('${planMoney(unscheduled)} of the quote not yet scheduled',
                  style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.warningDeep)),
            ),
          if (p.records.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: PlanHint(isMilestone ? noMilestonesText : 'No instalments on this plan.'),
            ),
          for (int i = 0; i < p.records.length; i++)
            _scheduleRow(context, p, p.records[i], attention,
                accounting: accounting, canRecord: canRecord, last: i == p.records.length - 1 && p.ownerName.isEmpty),
          if (p.ownerName.isNotEmpty) _ownerFooter(p),
        ],
      ),
    );
  }

  Widget _ownerFooter(PlanDetail p) {
    final parts = p.ownerName.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final initials = parts.take(2).map((s) => s[0].toUpperCase()).join();
    return Container(
      padding: EdgeInsets.only(top: 13.h),
      child: Row(
        children: [
          Container(
            width: 38.w,
            height: 38.w,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
            child: Text(initials.isEmpty ? '?' : initials,
                style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.white)),
          ),
          SizedBox(width: 11.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.ownerName, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                Text('Collection owner${p.ownerEmail.isNotEmpty ? ' · ${p.ownerEmail}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleRow(BuildContext context, PlanDetail p, PlanRecord r, List<PlanAttention> attention,
      {required bool accounting, required bool canRecord, required bool last}) {
    final meta = recordStatusMeta(r);
    final cancelled = r.status == 'cancelled';
    final strike = cancelled ? TextDecoration.lineThrough : null;
    final method = paymentMethodLabel(r.method);
    final hint = amountDueHint(r);
    final quoted = quotedAmountNote(r);
    final notes = [
      ...adjustmentLines(credited: r.amountCredited, refunded: r.amountRefunded, refundNotDue: r.amountRefundNotDue),
      if (r.cancelReason.isNotEmpty) r.cancelReason,
    ];
    final dateColor = r.status == 'paid'
        ? AppColors.success
        : r.status == 'overdue'
            ? AppColors.error
            : AppColors.textMuted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.paymentDetail}?id=${r.id}'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconChip(icon: planMethodIcon(r.method), iconSize: 18),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.displayLabel,
                      style: AppText.custom(
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: cancelled ? AppColors.textMuted : AppColors.textPrimary)
                          .copyWith(decoration: strike)),
                  SizedBox(height: 2.h),
                  Text(method.isEmpty ? '—' : method,
                      style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  SizedBox(height: 2.h),
                  Text(recordRowDate(r),
                      style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: dateColor)),
                  if (r.isLinkedToDocument) _tag(PhosphorIconsRegular.link, 'Linked to tax invoice', AppColors.navy),
                  if (isBlockedForCustomer(r, attention))
                    _tag(PhosphorIconsRegular.warning, 'Blocked: customer required', AppColors.warningDeep),
                  for (final n in notes)
                    Padding(
                      padding: EdgeInsets.only(top: 3.h),
                      child: Text(n, style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textMuted)),
                    ),
                  if (accounting) ..._accountingLine(context, r, p.customerId),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(planMoney(r.amountDueInclGst),
                    style: AppText.custom(size: 14, weight: FontWeight.w800, color: cancelled ? AppColors.textMuted : AppColors.navy)
                        .copyWith(decoration: strike)),
                if (hint.isNotEmpty)
                  Text(hint, style: AppText.custom(size: 10.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                if (quoted.isNotEmpty)
                  Text(quoted, style: AppText.custom(size: 10.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                if (r.settlementState == 'partly_paid')
                  Text('Balance ${planMoney(r.balanceDue)}',
                      style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                SizedBox(height: 5.h),
                StatusPill.meta(meta),
                if (canSettleRecord(r, canRecord: canRecord)) ...[
                  SizedBox(height: 6.h),
                  PlanButton(
                    label: 'Settle',
                    icon: PhosphorIconsRegular.checkCircle,
                    color: AppColors.success,
                    height: 32,
                    onTap: () => _openRecordSheet(context, p, recordId: r.id),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text, Color color) => Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11.sp, color: color),
            SizedBox(width: 4.w),
            Flexible(child: Text(text, style: AppText.custom(size: 11, weight: FontWeight.w700, color: color))),
          ],
        ),
      );

  /// The instalment's accounting state (accounting active only): the invoice
  /// raised for it, whether a receipt posted, and — with no invoice yet —
  /// "Issue invoice".
  List<Widget> _accountingLine(BuildContext context, PlanRecord r, String customerId) {
    final doc = r.document;
    final canCreate = ref.watch(accPermProvider('acc_document')).create;
    return [
      if (doc != null) ...[
        SizedBox(height: 5.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('${Routes.accDocumentDetail}?id=${doc.id}'),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.receipt, size: 12.sp, color: AppColors.blueBright),
              SizedBox(width: 4.w),
              Flexible(
                child: Text(doc.number.isNotEmpty ? doc.number : 'Draft invoice',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.blueBright)),
              ),
              if (doc.paymentState.isNotEmpty && doc.paymentState != 'NA' && doc.status == 'ISSUED') ...[
                SizedBox(width: 6.w),
                PaymentStatePill(doc.paymentState),
              ],
            ],
          ),
        ),
      ],
      if (r.postedReceiptId.isNotEmpty || r.receipt != null) ...[
        SizedBox(height: 4.h),
        Text('Receipt posted', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.success)),
      ],
      if (!r.isLinkedToDocument && doc == null && r.status != 'cancelled' && canCreate) ...[
        SizedBox(height: 5.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final created = await showInvoiceFromRecordSheet(context, recordId: r.id, customerId: customerId.isEmpty ? null : customerId);
            if (created != null && context.mounted) {
              context.push('${Routes.accDocumentDetail}?id=${created.id}');
            }
          },
          child: Text('Issue invoice',
              style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.blueBright)),
        ),
      ],
    ];
  }

  // ── Notes ──

  /// The plan's notes thread, hung off the **source quotation** — `payment`
  /// is not an accepted `related_to` model, so a plan and its quote share one
  /// thread. A plan with no source quote keeps a local-only thread.
  Widget _notesCard(PlanDetail p) {
    final quoteUuid = p.quotationUuid;
    final seed = CrmNotesSeed(
      quoteUuid.isEmpty ? 'PLAN-${p.id}' : quoteUuid,
      () => const <notes_model.NoteEntry>[],
      apiModel: quoteUuid.isEmpty ? null : 'quotation',
    );
    final thread = ref.watch(crmNotesProvider(seed));
    return NotesCard(
      notes: [
        for (final n in thread)
          NoteEntry(initials: _initialsOf(n.author), author: n.author, time: n.time, body: n.body),
      ],
      countLabel: thread.isEmpty ? null : '${thread.length}',
      onSend: (body) {
        ref.read(crmNotesProvider(seed).notifier).addNote(body, const [], ref.read(noteAuthorProvider));
        ref.read(toastProvider.notifier).show('Note added');
      },
    );
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

/// PAY-13 — marks a plan whose deal is still a lead (no customer yet).
class _LeadBadge extends StatelessWidget {
  const _LeadBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
        decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(4.r)),
        child: Text('LEAD', style: AppText.custom(size: 9.5, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.3)),
      );
}
