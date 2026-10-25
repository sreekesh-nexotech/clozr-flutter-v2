import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../application/providers/lead_lifecycle_providers.dart';

// Sheets for the webapp's Lost modal (`LostReasonModal` / `CustomerLostModal`)
// and its convert dialogs (`Convert to customer?` / `ConvertCustomerMatchDialog`),
// laid out as the app's bottom sheets with the webapp's copy.

/// Asks why [kind] (`lead` | `customer`) [recordId] is moving to the Lost
/// status [statusName]. Returns the choice, or null when cancelled.
Future<LostChoice?> showLostReasonSheet(
  BuildContext context, {
  required String kind,
  required String recordId,
  required String statusName,
}) {
  return showClozrSheet<LostChoice>(
    context: context,
    builder: (_) => _LostReasonSheet(kind: kind, recordId: recordId, statusName: statusName),
  );
}

class _LostReasonSheet extends ConsumerStatefulWidget {
  const _LostReasonSheet({required this.kind, required this.recordId, required this.statusName});

  final String kind;
  final String recordId;
  final String statusName;

  @override
  ConsumerState<_LostReasonSheet> createState() => _LostReasonSheetState();
}

class _LostReasonSheetState extends ConsumerState<_LostReasonSheet> {
  final _note = TextEditingController();
  String? _reasonId;

  bool get _isCustomer => widget.kind == 'customer';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reasons = ref.watch(leadLostReasonsProvider);
    final impactAsync = ref.watch(lostImpactProvider((widget.kind, widget.recordId)));
    final impact = impactAsync.valueOrNull;
    final checking = impactAsync.isLoading;
    final options = reasons.valueOrNull ?? const [];
    final blocked = impact?.blocked ?? false;
    final credit = impact != null && impact.hasOpenInvoices && impact.canCredit;
    final noun = _isCustomer ? 'customer' : 'lead';

    final label = checking
        ? (_isCustomer ? 'Checking deals…' : 'Checking invoices…')
        : credit
            ? 'Issue credit notes and mark Lost'
            : 'Mark as lost';
    final canConfirm = !checking && !blocked && _reasonId != null;

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
                  Text('Why was this $noun lost? The reason shows on the $noun and in reports.',
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
                    Text(
                        'A lost reason is required. Ask an administrator to add lost reasons in Settings → Leads.',
                        style: AppText.caption(color: AppColors.error))
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
                    hint: _isCustomer
                        ? 'Anything worth remembering'
                        : 'Anything worth remembering — e.g. chose a competitor on price',
                  ),
                  if (impact != null) ..._impactNotice(impact),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
            child: Row(
              children: [
                Expanded(
                  child: PrimaryButton(label: 'Cancel', ghost: true, onTap: () => Navigator.of(context).pop()),
                ),
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
                              creditOpenInvoices: credit,
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

  List<Widget> _impactNotice(LostImpact impact) {
    final out = <Widget>[];
    Widget box(List<Widget> children, {Color bg = AppColors.tintAmber}) => Container(
          width: double.infinity,
          margin: EdgeInsets.only(top: 14.h),
          padding: EdgeInsets.all(12.r),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );
    final caption = AppText.caption(color: AppColors.textSecondary);

    if (impact.hasOpenInvoices) {
      final n = impact.openInvoices.length;
      out.add(box([
        Text(
            '$n invoice${n == 1 ? '' : 's'} (${formatMoneyStr(impact.openAmountDue)}) '
            '${n == 1 ? 'is' : 'are'} issued but unpaid — issuing credit notes will cancel '
            '${n == 1 ? 'it' : 'them'}.',
            style: AppText.captionStrong(color: AppColors.textPrimary)),
        SizedBox(height: 6.h),
        for (final inv in impact.openInvoices)
          Text('${inv.leadName != null ? '${inv.leadName}: ' : ''}${inv.number} · ${inv.date} · '
              '${formatMoneyStr(inv.amountDue)} due', style: caption),
        if (!impact.canCredit) ...[
          SizedBox(height: 6.h),
          Text(
              'Ask your accounts team to issue credit notes for these invoices. The '
              '${_isCustomer ? 'customer' : 'lead'} can be marked Lost once they are credited.',
              style: AppText.caption(color: AppColors.error)),
        ],
      ]));
    }

    if (_isCustomer) {
      final items = <String>[
        if (impact.openInstalments > 0)
          '${impact.openInstalments} open instalment${impact.openInstalments == 1 ? '' : 's'} '
              '(${formatMoneyStr(impact.openInstalmentsAmount)}) and their follow-up tasks are cancelled',
        if (impact.draftInvoices > 0)
          impact.draftInvoices == 1 ? '1 draft invoice is voided' : '${impact.draftInvoices} draft invoices are voided',
        if (impact.otherQuotes.isNotEmpty)
          '${impact.otherQuotes.length} other quote${impact.otherQuotes.length == 1 ? ' of this customer is' : 's of this customer are'} '
              'closed the same way: ${impact.otherQuotes.join(', ')}',
        if (impact.upsellLeads.isNotEmpty)
          '${impact.upsellLeads.length} open upsell lead${impact.upsellLeads.length == 1 ? ' moves' : 's move'} '
              'to Lost with the same reason: ${impact.upsellLeads.join(', ')}',
      ];
      if (items.isNotEmpty || impact.moneyReceived > 0) {
        out.add(box([
          if (items.isNotEmpty) ...[
            Text('Marking this customer Lost closes its open deals:',
                style: AppText.captionStrong(color: AppColors.textPrimary)),
            SizedBox(height: 6.h),
            for (final i in items) Text('• $i', style: caption),
          ],
          if (impact.moneyReceived > 0) ...[
            if (items.isNotEmpty) SizedBox(height: 8.h),
            Text(
                '${formatMoneyStr(impact.moneyReceived)} already received stays with the customer as credit'
                '${impact.customerCredit != null ? ' (unapplied credit now ${formatMoneyStr(impact.customerCredit)})' : ''}. '
                'Nothing is refunded automatically.',
                style: caption),
            SizedBox(height: 4.h),
            Text.rich(TextSpan(children: [
              TextSpan(text: 'Next step: Refund via Accounts', style: AppText.captionStrong(color: AppColors.textPrimary)),
              TextSpan(text: ' — only if the customer asks for the money back.', style: caption),
            ])),
          ],
        ], bg: AppColors.bgLight));
      }
    }
    return out;
  }
}

/// The webapp's `Convert to customer?` confirm. Returns true to go ahead.
Future<bool> confirmConvertLead(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Convert to customer?'),
      content: const Text('A customer record is created from this lead. The lead is then frozen — '
          'its fields are edited on the customer from that point on.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Convert')),
      ],
    ),
  );
  return ok == true;
}

/// The user's answer to a `CUSTOMER_MATCH`: attach to an existing customer or
/// create a new one under a fresh name — exactly the convert body to resend.
Future<Map<String, dynamic>?> showCustomerMatchSheet(BuildContext context, CustomerMatch match) {
  return showClozrSheet<Map<String, dynamic>>(
    context: context,
    builder: (_) => _CustomerMatchSheet(match: match),
  );
}

class _CustomerMatchSheet extends StatefulWidget {
  const _CustomerMatchSheet({required this.match});

  final CustomerMatch match;

  @override
  State<_CustomerMatchSheet> createState() => _CustomerMatchSheetState();
}

class _CustomerMatchSheetState extends State<_CustomerMatchSheet> {
  late final _name = TextEditingController(text: widget.match.suggestedName);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final problem = m.nameProblem(_name.text);
    final caption = AppText.caption(color: AppColors.textMuted);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'This customer may already exist'),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.message, style: AppText.body(color: AppColors.textMuted)),
                  if (m.candidates.isNotEmpty) ...[
                    SizedBox(height: 14.h),
                    Text('Attach this lead to an existing customer', style: AppText.sectionTitle()),
                    SizedBox(height: 8.h),
                    for (final c in m.candidates)
                      Container(
                        margin: EdgeInsets.only(bottom: 8.h),
                        padding: EdgeInsets.all(12.r),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: AppColors.borderCardSoft),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${c.name}${c.reference.isNotEmpty ? ' · ${c.reference}' : ''}',
                                      style: AppText.bodyStrong()),
                                  if (c.email.isNotEmpty || c.phone.isNotEmpty)
                                    Text([c.email, c.phone].where((s) => s.isNotEmpty).join(' · '), style: caption),
                                  SizedBox(height: 4.h),
                                  Text(c.matchLabel, style: AppText.captionStrong(color: AppColors.blueBright)),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop({'attach_to_customer_id': c.id}),
                              child: const Text('Attach'),
                            ),
                          ],
                        ),
                      ),
                    Text('The lead becomes a new deal of that customer: its products and quotes move there, '
                        'and the customer keeps its own details.', style: caption),
                  ],
                  if (m.hiddenCount > 0) ...[
                    SizedBox(height: 8.h),
                    Text(
                        m.hiddenCount == 1
                            ? 'One matching customer is not visible to you. Ask your manager or an admin if the lead belongs to it.'
                            : '${m.hiddenCount} matching customers are not visible to you. Ask your manager or an admin if the lead belongs to one of them.',
                        style: caption),
                  ],
                  SizedBox(height: 18.h),
                  Text('Or create a new customer', style: AppText.sectionTitle()),
                  SizedBox(height: 8.h),
                  AppTextField(
                    label: 'New customer name',
                    controller: _name,
                    errorText: _name.text.isEmpty ? null : problem,
                  ),
                  SizedBox(height: 12.h),
                  PrimaryButton(
                    label: 'Create new customer',
                    icon: PhosphorIconsBold.plus,
                    onTap: problem == null
                        ? () => Navigator.of(context).pop({
                              'create_new_customer': true,
                              'customer_name': _name.text.trim(),
                            })
                        : null,
                  ),
                  SizedBox(height: 8.h),
                  PrimaryButton(label: 'Cancel', ghost: true, onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
