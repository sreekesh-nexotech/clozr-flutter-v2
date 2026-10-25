import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/network/app_error.dart';
import '../../../../../core/network/network_providers.dart';
import '../../../../accounting/presentation/sheets/acc_sheet_scaffold.dart' show confirmAcc;
import '../../../../auth/presentation/components/permission_guard.dart';
import '../../../../shell/application/providers/shell_providers.dart';
import '../../../application/payment_plan/payment_plan_detail.dart';
import '../../../application/payment_plan/payment_plan_rules.dart';
import '../../../application/providers/invoices_providers.dart';
import '../../../application/providers/payment_plan_providers.dart';
import '../../../application/providers/payments_providers.dart';
import '../finance_widgets.dart';
import 'plan_widgets.dart';

/// "Recurring schedule" (PY-029, webapp `RecurringScheduleCard`): the header,
/// progress (periods paid ÷ periods elapsed) and "Stop recurring from <date>".
/// Render only for a plan with `recurring`.
class RecurringScheduleCard extends ConsumerStatefulWidget {
  const RecurringScheduleCard({super.key, required this.plan, required this.canEdit});

  final PlanDetail plan;

  /// Payment update.
  final bool canEdit;

  @override
  ConsumerState<RecurringScheduleCard> createState() => _RecurringScheduleCardState();
}

class _RecurringScheduleCardState extends ConsumerState<RecurringScheduleCard> {
  late String _stopFrom;
  String? _failure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _stopFrom = defaultStopFrom(widget.plan.recurring!);
  }

  Future<void> _stop() async {
    if (!ensurePermission(ref, 'payment', PermVerb.update)) return;
    final label = planDate(_stopFrom).isEmpty ? _stopFrom : planDate(_stopFrom);
    final ok = await confirmAcc(
      context,
      title: 'Stop recurring billing?',
      body: stopRecurringBody(label),
      confirmLabel: 'Stop recurring',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(paymentPlanRemoteProvider).stopRecurring(widget.plan.id, _stopFrom);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Recurring billing stops from $label');
      ref.invalidate(paymentPlanDetailProvider(widget.plan.id));
      ref.invalidate(invoicesProvider);
      ref.invalidate(paymentsProvider);
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) setState(() => _failure = e.bareMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.plan.recurring!;
    final canStop = r.canStop && planStatusKey(widget.plan) != 'completed';
    return FinanceCard(
      title: 'Recurring schedule',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.header.isNotEmpty ? r.header : r.periodsPaidLabel,
              style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 10.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: LinearProgressIndicator(
              value: r.progressPct / 100,
              minHeight: 8.h,
              backgroundColor: AppColors.bgLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.success),
            ),
          ),
          SizedBox(height: 6.h),
          PlanHint(recurringProgressText(r)),
          if (_failure != null) ...[
            SizedBox(height: 12.h),
            PlanInlineError(_failure!),
          ],
          if (canStop) ...[
            SizedBox(height: 14.h),
            PlanDateField(
              label: 'Stop recurring from',
              isoValue: _stopFrom,
              enabled: widget.canEdit && !_busy,
              onTap: () async {
                final picked = await pickPlanDate(context, _stopFrom,
                    firstIso: r.firstPeriodStart.isEmpty ? null : r.firstPeriodStart);
                if (picked != null && mounted) setState(() => _stopFrom = picked);
              },
            ),
            SizedBox(height: 12.h),
            Align(
              alignment: Alignment.centerRight,
              child: PlanButton(
                label: _busy ? 'Stopping…' : 'Stop recurring',
                icon: PhosphorIconsRegular.stopCircle,
                color: AppColors.error,
                busy: _busy,
                onTap: _stopFrom.isEmpty ? null : _stop,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
