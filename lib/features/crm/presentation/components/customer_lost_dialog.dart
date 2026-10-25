import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../application/customer_detail_rules.dart';
import '../../application/providers/lead_lifecycle_providers.dart';

/// `GET /crm/customers/{id}/lost-impact/` — always fresh (an invoice can be
/// paid or credited at any time). Null when the check itself failed: the
/// move may then go ahead and the server's own 409 guard still applies.
final customerLostImpactProvider =
    FutureProvider.autoDispose.family<CustomerLostImpact?, String>((ref, id) async {
  if (id.isEmpty) return null;
  try {
    final body = await ref.read(apiServiceProvider).get(ApiEndpoints.customerLostImpact(id), quiet: true);
    return CustomerLostImpact.fromJson(body) ?? const CustomerLostImpact();
  } on AppError {
    return null;
  }
});

/// The webapp's `CustomerLostModal` as a bottom sheet: "Move to <status>",
/// a required lost reason, an optional note, and what the move closes.
/// [blocked] are the impacts a `409 LOST_HAS_OPEN_INVOICES` reported (the
/// sheet re-opens listing them). Returns the choice, or null when cancelled.
Future<LostChoice?> showCustomerLostDialog(
  BuildContext context, {
  required String customerId,
  required String statusName,
  List<CustomerLostImpact> blocked = const [],
}) {
  return showClozrSheet<LostChoice>(
    context: context,
    builder: (_) => _CustomerLostSheet(customerId: customerId, statusName: statusName, blocked: blocked),
  );
}

class _CustomerLostSheet extends ConsumerStatefulWidget {
  const _CustomerLostSheet({required this.customerId, required this.statusName, required this.blocked});

  final String customerId;
  final String statusName;
  final List<CustomerLostImpact> blocked;

  @override
  ConsumerState<_CustomerLostSheet> createState() => _CustomerLostSheetState();
}

class _CustomerLostSheetState extends ConsumerState<_CustomerLostSheet> {
  final _note = TextEditingController();
  String? _reasonId;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reasons = ref.watch(leadLostReasonsProvider);
    final impactAsync = ref.watch(customerLostImpactProvider(widget.customerId));
    final impact = impactAsync.valueOrNull;
    final invoiceImpacts = widget.blocked.isNotEmpty
        ? widget.blocked
        : (impact != null && impact.hasOpenInvoices ? [impact] : const <CustomerLostImpact>[]);
    final needsCredit = invoiceImpacts.isNotEmpty;
    final anyCanCredit = invoiceImpacts.any((i) => i.canCredit);
    final allCanCredit = needsCredit && invoiceImpacts.every((i) => i.canCredit);
    final blockedSingle = needsCredit && !allCanCredit;
    final checking = impactAsync.isLoading && widget.blocked.isEmpty;
    final options = reasons.valueOrNull ?? const [];
    final canConfirm = !checking && !blockedSingle && _reasonId != null;
    final label = checking
        ? 'Checking deals…'
        : needsCredit && anyCanCredit
            ? 'Issue credit notes and mark Lost'
            : 'Mark as lost';
    final received = impact == null ? null : describeMoneyReceived(impact);
    final summary = impact == null ? const <String>[] : lostSummaryLines(impact);
    final caption = AppText.caption(color: AppColors.textSecondary);

    Widget box(List<Widget> children, {Color bg = AppColors.bgLight, Color? border}) => Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: 14.h),
          padding: EdgeInsets.all(12.r),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10.r),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Move to ${widget.statusName}'),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (needsCredit)
                    box([
                      Text(
                        describeOpenInvoices(
                          invoiceImpacts.fold<int>(0, (n, i) => n + i.openInvoices.length),
                          invoiceImpacts.fold<num>(0, (n, i) => n + i.amountDue),
                        ),
                        style: AppText.captionStrong(color: AppColors.textPrimary),
                      ),
                      SizedBox(height: 6.h),
                      for (final i in invoiceImpacts)
                        for (final inv in i.openInvoices)
                          Text('• ${inv.number}${inv.date != null ? ' · ${inv.date}' : ''} · ${lostMoney(inv.amountDue)} due',
                              style: caption),
                      if (!allCanCredit) ...[
                        SizedBox(height: 6.h),
                        Text(
                          'Ask your accounts team to issue credit notes for these invoices. '
                          'The customer can be marked Lost once they are credited.',
                          style: AppText.caption(color: AppColors.error),
                        ),
                      ],
                    ], bg: AppColors.white, border: allCanCredit ? AppColors.warning : AppColors.error),
                  if (summary.isNotEmpty)
                    box([
                      Text(lostSummaryHeading, style: AppText.captionStrong(color: AppColors.textPrimary)),
                      SizedBox(height: 6.h),
                      for (final s in summary) Text('• $s', style: caption),
                    ]),
                  if (received != null)
                    box([
                      Text.rich(TextSpan(children: [
                        TextSpan(text: '$received ', style: caption),
                        TextSpan(
                            text: 'Next step: Refund via Accounts',
                            style: AppText.captionStrong(color: AppColors.textPrimary)),
                        TextSpan(text: ' — only if the customer asks for the money back.', style: caption),
                      ])),
                    ], bg: AppColors.tintBlue),
                  Text('Why was this customer lost? The reason shows on the customer and in reports.',
                      style: AppText.body(color: AppColors.textMuted)),
                  SizedBox(height: 14.h),
                  Text('Lost reason (required)', style: AppText.captionStrong(color: AppColors.textSecondary)),
                  SizedBox(height: 8.h),
                  if (reasons.isLoading)
                    Text('Loading reasons…', style: AppText.caption())
                  else if (reasons.hasError)
                    Text('Couldn’t load the reasons. Close this and try again.',
                        style: AppText.caption(color: AppColors.error))
                  else if (options.isEmpty)
                    Text(noLostReasonsCopy, style: AppText.caption(color: AppColors.error))
                  else
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [
                        for (final o in options)
                          ChoiceChip(
                            label: Text(o.name),
                            selected: _reasonId == o.id,
                            onSelected: (_) => setState(() => _reasonId = o.id),
                          ),
                      ],
                    ),
                  SizedBox(height: 16.h),
                  AppTextField(
                    label: 'Note (optional)',
                    controller: _note,
                    multiline: true,
                    hint: 'Anything worth remembering',
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
            child: Row(
              children: [
                Expanded(child: PrimaryButton(label: 'Cancel', ghost: true, onTap: () => Navigator.of(context).pop())),
                SizedBox(width: 10.w),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    label: label,
                    color: AppColors.error,
                    onTap: canConfirm
                        ? () => Navigator.of(context).pop(LostChoice(
                              reasonId: _reasonId!,
                              note: _note.text,
                              creditOpenInvoices: needsCredit && anyCanCredit,
                            ))
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
