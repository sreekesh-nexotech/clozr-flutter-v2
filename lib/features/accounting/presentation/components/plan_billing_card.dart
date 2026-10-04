import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../crm/application/providers/invoices_providers.dart';
import '../../../crm/domain/entities/invoice.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../../operations/application/providers/projects_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../config/accounting_copy.dart';
import 'acc_pickers.dart';
import 'acc_widgets.dart';

/// "Billing settings" on a payment plan (plan §5.2, handover §9.2): how the
/// plan becomes invoices, whether due drafts issue themselves, the tax basis,
/// the project and a contract reference. Each change saves on its own —
/// `PATCH /quotations/payments/{id}/`.
///
/// Shown only while accounting is active; the caller decides that.
class PlanBillingCard extends ConsumerStatefulWidget {
  const PlanBillingCard({super.key, required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<PlanBillingCard> createState() => _PlanBillingCardState();
}

class _PlanBillingCardState extends ConsumerState<PlanBillingCard> {
  bool _saving = false;

  Future<void> _save(Map<String, Object?> fields, String done) async {
    if (_saving || widget.invoice.uuid.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(invoicesRepositoryProvider).updatePlanBilling(widget.invoice.uuid, fields);
      ref.invalidate(invoicesProvider);
      if (mounted) ref.read(toastProvider.notifier).show(done);
    } on AppError catch (e) {
      // `amounts_are` locks once anything is linked — the field error says so.
      if (mounted) ref.read(toastProvider.notifier).showError(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final iv = widget.invoice;
    final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
    final project = iv.projectId == null ? null : projects.where((p) => p.id == iv.projectId).firstOrNull;
    return Opacity(
      opacity: _saving ? 0.6 : 1,
      child: FinanceCard(
        title: 'Billing settings',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (iv.amountsAre == null) ...[
              SizedBox(height: 6.h),
              const AccInfoBanner(
                'Choose whether this plan\'s prices include tax. Accounting needs it before any instalment can be invoiced.',
                icon: PhosphorIconsRegular.warning,
              ),
            ],
            SizedBox(height: 10.h),
            AccChoiceChips(
              label: 'Invoices are raised',
              options: billingModeLabels,
              selected: iv.billingMode,
              onSelected: (v) => _save({'billing_mode': v}, 'Billing mode saved'),
            ),
            if (iv.billingMode != null) ...[
              SizedBox(height: 6.h),
              Text(billingModeHelp[iv.billingMode] ?? '',
                  style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
            ],
            if (iv.billingMode == 'INVOICE_ON_DUE' || iv.billingMode == 'PERIODIC') ...[
              SizedBox(height: 12.h),
              AccCheckRow(
                label: 'Issue automatically when due',
                hint: 'Otherwise the draft waits for someone to issue it.',
                value: iv.autoIssue,
                onChanged: (v) => _save({'auto_issue': v}, v ? 'Auto-issue on' : 'Auto-issue off'),
              ),
            ],
            SizedBox(height: 13.h),
            AccChoiceChips(
              label: 'Prices are',
              options: amountsAreLabels,
              selected: iv.amountsAre,
              onSelected: (v) => _save({'amounts_are': v}, 'Tax basis saved'),
            ),
            SizedBox(height: 13.h),
            AccPickerBox(
              label: 'Project',
              value: project?.name ?? (iv.projectId == null ? null : 'Linked project'),
              hint: 'None',
              icon: PhosphorIconsRegular.kanban,
              onTap: () async {
                final id = await showSearchPicker<String>(
                  context: context,
                  title: 'Project',
                  selected: iv.projectId,
                  empty: 'No projects',
                  items: [for (final p in projects) PickItem(p.id, p.name, subtitle: p.code)],
                );
                if (id != null) await _save({'project': id}, 'Project linked');
              },
            ),
            SizedBox(height: 13.h),
            _ContractRef(initial: iv.contractRef ?? '', onSave: (v) => _save({'contract_ref': v}, 'Contract reference saved')),
          ],
        ),
      ),
    );
  }
}

/// The contract reference box — saved on done, not per keystroke.
class _ContractRef extends StatefulWidget {
  const _ContractRef({required this.initial, required this.onSave});
  final String initial;
  final ValueChanged<String> onSave;

  @override
  State<_ContractRef> createState() => _ContractRefState();
}

class _ContractRefState extends State<_ContractRef> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _ctrl.text.trim();
    if (v != widget.initial) widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (has) {
        if (!has) _commit();
      },
      child: AccInput(label: 'Contract reference', controller: _ctrl, hint: 'Optional — PO or contract no.'),
    );
  }
}
