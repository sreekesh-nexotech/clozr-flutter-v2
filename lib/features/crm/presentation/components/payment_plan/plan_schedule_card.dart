import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../core/network/app_error.dart';
import '../../../../../core/network/network_providers.dart';
import '../../../../../core/widgets/app_text_field.dart';
import '../../../../auth/presentation/components/permission_guard.dart';
import '../../../../shell/application/providers/shell_providers.dart';
import '../../../application/payment_plan/payment_plan_detail.dart';
import '../../../application/payment_plan/payment_plan_rules.dart';
import '../../../application/providers/invoices_providers.dart';
import '../../../application/providers/payment_plan_providers.dart';
import '../../../application/providers/payments_providers.dart';
import '../finance_widgets.dart';
import 'plan_widgets.dart';

/// "Instalments" (PY-027, webapp `PlanScheduleCard`): split a plan that has
/// nothing paid or invoiced into instalments — how many, how many days apart,
/// the first due date. The server sets the exact amounts. Render only when
/// `canChooseInstalments(plan)`.
class PlanScheduleCard extends ConsumerStatefulWidget {
  const PlanScheduleCard({super.key, required this.plan, required this.canEdit});

  final PlanDetail plan;

  /// Payment update.
  final bool canEdit;

  @override
  ConsumerState<PlanScheduleCard> createState() => _PlanScheduleCardState();
}

class _PlanScheduleCardState extends ConsumerState<PlanScheduleCard> {
  late final TextEditingController _count;
  late final TextEditingController _days;
  late String _firstDue;
  Map<String, String> _errors = const {};
  String? _failure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final d = initialScheduleDraft(widget.plan);
    _count = TextEditingController(text: d.count);
    _days = TextEditingController(text: d.periodDays);
    _firstDue = d.firstDueDate;
  }

  @override
  void dispose() {
    _count.dispose();
    _days.dispose();
    super.dispose();
  }

  ScheduleDraft get _draft => ScheduleDraft(count: _count.text, periodDays: _days.text, firstDueDate: _firstDue);

  void _changed() => setState(() {
        _errors = const {};
        _failure = null;
      });

  Future<void> _save() async {
    if (!ensurePermission(ref, 'payment', PermVerb.update)) return;
    final draft = _draft;
    final errors = validateScheduleDraft(draft);
    setState(() {
      _errors = errors;
      _failure = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final ds = ref.read(paymentPlanRemoteProvider);
    try {
      var saved = await ds.schedulePlan(widget.plan.id, scheduleBody(draft));
      if (saved.id.isEmpty) saved = await ds.getPlan(widget.plan.id);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(scheduleSavedToast(saved));
      ref.invalidate(paymentPlanDetailProvider(widget.plan.id));
      ref.invalidate(invoicesProvider);
      ref.invalidate(paymentsProvider);
    } on AppError catch (e) {
      // Shown inline — 409 PLAN_SCHEDULE_LOCKED when a payment raced in.
      ref.read(apiServiceProvider).handled(e);
      if (mounted) setState(() => _failure = e.bareMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.canEdit && !_busy;
    final preview = schedulePreviewText(widget.plan.totalInclGst, _draft);
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)];
    return FinanceCard(
      title: 'Instalments',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PlanHint('Split this plan into instalments. Possible until a payment is recorded or an instalment is invoiced.'),
          SizedBox(height: 12.h),
          if (_failure != null) ...[
            PlanInlineError(_failure!),
            SizedBox(height: 12.h),
          ],
          AbsorbPointer(
            absorbing: !enabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Number of instalments',
                  controller: _count,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  onChanged: (_) => _changed(),
                  errorText: _errors['count'],
                ),
                if (_errors['count'] == null) ...[
                  SizedBox(height: 5.h),
                  const PlanHint('1 = a single payment (up to $maxInstalments).'),
                ],
                SizedBox(height: 12.h),
                AppTextField(
                  label: 'Days between instalments',
                  controller: _days,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  onChanged: (_) => _changed(),
                  errorText: _errors['periodDays'],
                ),
                if (_errors['periodDays'] == null) ...[
                  SizedBox(height: 5.h),
                  const PlanHint('e.g. 30 for monthly (1–$maxPeriodDays).'),
                ],
                SizedBox(height: 12.h),
                PlanDateField(
                  label: 'First due date',
                  isoValue: _firstDue,
                  enabled: enabled,
                  onTap: () async {
                    final picked = await pickPlanDate(context, _firstDue);
                    if (picked != null && mounted) {
                      _firstDue = picked;
                      _changed();
                    }
                  },
                ),
              ],
            ),
          ),
          if (preview.isNotEmpty) ...[
            SizedBox(height: 12.h),
            PlanHint(preview),
          ],
          SizedBox(height: 14.h),
          Align(
            alignment: Alignment.centerRight,
            child: PlanButton(
              label: _busy ? 'Saving…' : 'Save instalments',
              icon: PhosphorIconsBold.check,
              filled: true,
              busy: _busy,
              onTap: _save,
            ),
          ),
        ],
      ),
    );
  }
}
