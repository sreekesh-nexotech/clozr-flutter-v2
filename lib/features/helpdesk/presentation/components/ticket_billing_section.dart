import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/presentation/components/acc_widgets.dart';
import '../../domain/entities/ticket.dart';
import 'ticket_form_fields.dart';

/// What the create / edit ticket forms hold for billing (plan §5.5, handover
/// §9.5): whether the work is billable, and for how much — an amount, a
/// catalog product, or both.
class TicketBillingDraft {
  TicketBillingDraft({this.billable = false, String amount = '', this.productId, this.productName})
      : amount = TextEditingController(text: amount);

  factory TicketBillingDraft.of(Ticket t) => TicketBillingDraft(
        billable: t.billable,
        amount: t.billableAmount ?? '',
        productId: t.billableProductId,
      );

  bool billable;
  final TextEditingController amount;
  String? productId;
  String? productName;

  void dispose() => amount.dispose();

  /// Null when fine; the reason otherwise. The backend refuses a billable
  /// ticket with neither an amount nor a product (a validation 400).
  String? get error =>
      billable && moneyInput(amount.text) == null && productId == null
          ? 'A billable ticket needs an amount or a product'
          : null;

  Map<String, Object?> toJson() => {
        'billable': billable,
        'billable_amount': billable ? moneyInput(amount.text) : null,
        'billable_product_id': billable ? productId : null,
      };
}

/// The "Billing" block on the ticket forms. Renders nothing unless accounting
/// is active. Once the ticket has been billed the fields lock — the invoice
/// line already carries them.
class TicketBillingSection extends ConsumerWidget {
  const TicketBillingSection({
    super.key,
    required this.draft,
    required this.onChanged,
    this.locked = false,
  });

  final TicketBillingDraft draft;
  final VoidCallback onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(accountingActiveProvider)) return const SizedBox.shrink();
    if (locked) {
      return Padding(
        padding: EdgeInsets.only(top: 14.h),
        child: const AccInfoBanner('This ticket has been billed, so its billing details are locked.',
            icon: PhosphorIconsRegular.lockSimple),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 14.h),
        AccCheckRow(
          label: 'Billable',
          hint: 'Charge the customer for this work.',
          value: draft.billable,
          onChanged: (v) {
            draft.billable = v;
            onChanged();
          },
        ),
        if (draft.billable) ...[
          SizedBox(height: 12.h),
          MoneyField(label: 'Amount', controller: draft.amount, hint: 'Optional if a product is picked', onChanged: (_) => onChanged()),
          SizedBox(height: 12.h),
          const TicketFieldLabel('Bill as product'),
          SizedBox(height: 7.h),
          TicketPickerRow(
            label: draft.productName ?? (draft.productId == null ? 'Optional — pick a product' : 'Linked product'),
            placeholder: draft.productId == null,
            icon: PhosphorIconsBold.caretRight,
            onTap: () async {
              final picked = await pickTicketProduct(context, ref, selectedId: draft.productId);
              if (picked == null) return;
              draft.productId = picked.id;
              draft.productName = picked.name;
              onChanged();
            },
          ),
          if (draft.error != null) ...[
            SizedBox(height: 6.h),
            Text(draft.error!, style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
          ],
        ],
      ],
    );
  }
}
