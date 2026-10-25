import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/network/app_error.dart';
import '../../../../../core/network/network_providers.dart';
import '../../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../../core/widgets/app_text_field.dart';
import '../../../../shell/application/providers/shell_providers.dart';
import '../../../application/payment_plan/payment_plan_detail.dart';
import '../../../application/payment_plan/payment_plan_rules.dart';
import '../../../application/providers/invoices_providers.dart';
import '../../../application/providers/payment_plan_providers.dart';
import '../../../application/providers/payments_providers.dart';
import '../../../application/providers/followups_providers.dart';
import '../../sheets/add_sheet_kit.dart' show SelectChip, SheetSubmitBar;
import 'plan_widgets.dart';

/// "Add milestone" (PY-028, webapp `AddMilestoneModal`): a label, an amount —
/// ₹ incl. GST or a % of the quote's total — and a due date, posted as a
/// pending record. The server converts it to the plan's basis and creates the
/// dues follow-up.
Future<void> showAddMilestoneSheet(BuildContext context, PlanDetail plan) => showClozrSheet<void>(
      context: context,
      builder: (_) => _AddMilestoneSheet(plan: plan),
    );

class _AddMilestoneSheet extends ConsumerStatefulWidget {
  const _AddMilestoneSheet({required this.plan});
  final PlanDetail plan;

  @override
  ConsumerState<_AddMilestoneSheet> createState() => _AddMilestoneSheetState();
}

class _AddMilestoneSheetState extends ConsumerState<_AddMilestoneSheet> {
  final _label = TextEditingController();
  final _amount = TextEditingController();
  bool _percent = false;
  String _due = '';
  Map<String, String> _errors = const {};
  String? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  double get _base => milestoneBaseTotal(widget.plan);

  void _changed() => setState(() {
        _errors = const {};
        _failure = null;
      });

  Future<void> _save() async {
    final errors = validateMilestone(
        label: _label.text, percent: _percent, amount: _amount.text, dueDate: _due, base: _base);
    final amount = milestoneAmount(percent: _percent, amount: _amount.text, base: _base);
    setState(() {
      _errors = errors;
      _failure = null;
    });
    if (errors.isNotEmpty || amount == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(paymentPlanRemoteProvider).addMilestone(
            milestoneBody(planId: widget.plan.id, label: _label.text, amountInclGst: amount, dueDate: _due),
          );
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(milestoneAddedToast(amount));
      ref.invalidate(paymentPlanDetailProvider(widget.plan.id));
      ref.invalidate(invoicesProvider);
      ref.invalidate(paymentsProvider);
      // The milestone's dues follow-up lands in CRM › Follow-ups.
      ref.invalidate(followupsProvider);
      Navigator.of(context).pop();
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) setState(() => _failure = e.bareMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = milestoneAmountNote(
        percent: _percent, amount: _amount.text, base: _base, unscheduled: widget.plan.unscheduledInclGst);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Add milestone', onClose: _busy ? () {} : null),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 16.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlanHint(milestoneIntro(widget.plan.quoteNumber, _base), color: AppColors.textSecondary),
                SizedBox(height: 14.h),
                if (_failure != null) ...[
                  PlanInlineError(_failure!),
                  SizedBox(height: 14.h),
                ],
                AppTextField(
                  label: 'Milestone',
                  hint: 'e.g. Design sign-off',
                  controller: _label,
                  inputFormatters: [LengthLimitingTextInputFormatter(milestoneLabelMax + 1)],
                  onChanged: (_) => _changed(),
                  errorText: _errors['label'],
                ),
                SizedBox(height: 14.h),
                Text('Amount', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                SizedBox(height: 7.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    SelectChip(
                      label: '₹ incl. GST',
                      selected: !_percent,
                      onTap: () {
                        _percent = false;
                        _changed();
                      },
                    ),
                    if (_base > 0)
                      SelectChip(
                        label: '% of the quote total',
                        selected: _percent,
                        onTap: () {
                          _percent = true;
                          _changed();
                        },
                      ),
                  ],
                ),
                SizedBox(height: 10.h),
                AppTextField(
                  label: _percent ? 'Share of the quote total (%)' : 'Amount incl. GST (₹)',
                  hint: _percent ? 'e.g. 40' : 'e.g. 25000',
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (_) => _changed(),
                  errorText: _errors['amount'],
                ),
                if (note.isNotEmpty && _errors['amount'] == null) ...[
                  SizedBox(height: 5.h),
                  PlanHint(note),
                ],
                SizedBox(height: 14.h),
                PlanDateField(
                  label: 'Due date',
                  isoValue: _due,
                  errorText: _errors['dueDate'],
                  onTap: () async {
                    final picked = await pickPlanDate(context, _due);
                    if (picked != null && mounted) {
                      _due = picked;
                      _changed();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        SheetSubmitBar(
          label: 'Add milestone',
          icon: PhosphorIconsBold.flag,
          busy: _busy,
          busyLabel: 'Adding…',
          onTap: _save,
        ),
      ],
    );
  }
}
