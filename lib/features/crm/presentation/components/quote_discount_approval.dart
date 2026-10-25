import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/quote_discount_approvals_providers.dart';
import '../../application/quote_discount_approval_rules.dart';
import 'due_date_change.dart' show dueDateLabel;

// Webapp `DiscountApprovalBanner` + `DiscountDecisionDialog` (plan 5.5). One
// import gives the detail screen and the list toolbar everything they need:
// the banner, the dialogs, the badge provider and the gating helpers.
export '../../application/providers/quote_discount_approvals_providers.dart'
    show quoteDiscountApprovalsBadgeProvider, quoteLatestDiscountApprovalProvider, invalidateAfterDiscountDecision;
export '../../application/quote_discount_approval_rules.dart'
    show
        markSentBlockedReason,
        acceptBlockedByApprovalReason,
        acceptBlockedReason,
        isSendBlockedByApproval,
        quoteApprovalStatus,
        approvalChipLabel,
        discountApprovalsLabel,
        pctLabel;

/// Detail strip for a discount above the creator's limit, from the quote
/// record ([row] = `GET /quotations/quotations/{uuid}/`): "Discount approval
/// pending." (Approve / Reject when the server says this user may decide) or
/// "Discount approval rejected." with the reviewer's comment. Renders nothing
/// for NOT_REQUIRED / APPROVED. [onChanged] runs after a decision (the
/// record, inbox, badge and quote list are already invalidated).
class DiscountApprovalBanner extends ConsumerWidget {
  const DiscountApprovalBanner({super.key, required this.row, required this.onChanged});

  final Map<String, dynamic>? row;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isSendBlockedByApproval(row)) return const SizedBox.shrink();
    final uuid = '${row?['quotation_id'] ?? ''}';
    final latest = ref.watch(quoteLatestDiscountApprovalProvider(uuid)).valueOrNull;
    final f = DiscountBannerFacts.from(row, latest);
    if (f == null) return const SizedBox.shrink();
    final number = '${row?['quotation_number'] ?? ''}'.trim();
    final title = '${row?['quotation_title'] ?? ''}'.trim();
    final label = number.isNotEmpty ? number : title;

    Future<void> decide(bool approve) async {
      final ok = await showDiscountDecisionDialog(
        context,
        ref,
        approve: approve,
        quotationUuid: uuid,
        quoteLabel: label,
        discountPct: f.discountPct,
        limitPct: f.limitPct,
      );
      if (ok) onChanged();
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 14.h),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: f.pending ? AppColors.tintAmber : AppColors.tintRed,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            f.pending ? PhosphorIconsRegular.hourglassMedium : PhosphorIconsRegular.xCircle,
            size: 16.sp,
            color: f.pending ? AppColors.warningDeep : AppColors.error,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text.rich(TextSpan(style: AppText.body(), children: [
              TextSpan(text: f.title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              TextSpan(text: f.body(dueDateLabel)),
            ])),
          ),
        ]),
        if (f.canDecide) ...[
          SizedBox(height: 10.h),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton.icon(
              onPressed: () => decide(false),
              icon: Icon(PhosphorIconsRegular.x, size: 14.sp),
              label: const Text('Reject'),
            ),
            SizedBox(width: 10.w),
            FilledButton.icon(
              onPressed: () => decide(true),
              icon: Icon(PhosphorIconsRegular.check, size: 14.sp),
              label: const Text('Approve'),
            ),
          ]),
        ],
      ]),
    );
  }
}

/// "Approve this discount?" — see [showDiscountDecisionDialog].
Future<bool> showApproveDiscountDialog(
  BuildContext context,
  WidgetRef ref, {
  required String quotationUuid,
  required String quoteLabel,
  required String discountPct,
  String? limitPct,
  String? inboxQuotationNumber,
}) =>
    showDiscountDecisionDialog(context, ref,
        approve: true,
        quotationUuid: quotationUuid,
        quoteLabel: quoteLabel,
        discountPct: discountPct,
        limitPct: limitPct,
        inboxQuotationNumber: inboxQuotationNumber);

/// "Reject this discount?" — see [showDiscountDecisionDialog].
Future<bool> showRejectDiscountDialog(
  BuildContext context,
  WidgetRef ref, {
  required String quotationUuid,
  required String quoteLabel,
  required String discountPct,
  String? limitPct,
  String? inboxQuotationNumber,
}) =>
    showDiscountDecisionDialog(context, ref,
        approve: false,
        quotationUuid: quotationUuid,
        quoteLabel: quoteLabel,
        discountPct: discountPct,
        limitPct: limitPct,
        inboxQuotationNumber: inboxQuotationNumber);

/// Webapp `DiscountDecisionDialog`: optional comment (max 1000) the requester
/// sees; posts the decision, invalidates the inbox / badge / quote, toasts and
/// returns true once decided. From the inbox pass [inboxQuotationNumber] —
/// toast "Discount on <number> approved/rejected"; from the banner leave it
/// null — toast "Discount approved" / "Discount rejected" (webapp copy).
Future<bool> showDiscountDecisionDialog(
  BuildContext context,
  WidgetRef ref, {
  required bool approve,
  required String quotationUuid,
  required String quoteLabel,
  required String discountPct,
  String? limitPct,
  String? inboxQuotationNumber,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _DecisionDialog(
      approve: approve,
      quotationUuid: quotationUuid,
      quoteLabel: quoteLabel,
      discountPct: discountPct,
      limitPct: limitPct,
    ),
  );
  if (done != true) return false;
  final n = inboxQuotationNumber;
  ref.read(toastProvider.notifier).show(n != null
      ? (approve ? 'Discount on $n approved' : 'Discount on $n rejected')
      : (approve ? 'Discount approved' : 'Discount rejected'));
  invalidateAfterDiscountDecision(ref, quotationUuid);
  return true;
}

class _DecisionDialog extends ConsumerStatefulWidget {
  const _DecisionDialog({
    required this.approve,
    required this.quotationUuid,
    required this.quoteLabel,
    required this.discountPct,
    required this.limitPct,
  });

  final bool approve;
  final String quotationUuid;
  final String quoteLabel;
  final String discountPct;
  final String? limitPct;

  @override
  ConsumerState<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends ConsumerState<_DecisionDialog> {
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(apiServiceProvider);
    try {
      await postQuoteDiscountDecision(api, widget.quotationUuid, approve: widget.approve, comment: _comment.text);
    } on AppError catch (e) {
      api.handled(e);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final approve = widget.approve;
    return AlertDialog(
      title: Text(approve ? 'Approve this discount?' : 'Reject this discount?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(style: AppText.body(), children: [
            TextSpan(text: widget.quoteLabel, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            TextSpan(
              text: discountDecisionBody(approve: approve, discountPct: widget.discountPct, limitPct: widget.limitPct),
            ),
          ])),
          SizedBox(height: 12.h),
          TextField(
            controller: _comment,
            enabled: !_busy,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Comment (optional)',
              hintText: approve ? 'e.g. OK for this strategic account' : 'e.g. Keep it within 10% — offer free onboarding instead',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) Text(_error!, style: AppText.caption(color: AppColors.error)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: Text(
            _busy ? 'Saving…' : (approve ? 'Approve discount' : 'Reject discount'),
            style: TextStyle(color: approve ? null : AppColors.error),
          ),
        ),
      ],
    );
  }
}

/// Optional toolbar entry for the Quotes list: a seal-check icon with a red
/// count badge (requests this user may decide) and the webapp tooltip.
class DiscountApprovalsToolbarButton extends ConsumerWidget {
  const DiscountApprovalsToolbarButton({super.key, required this.onTap, this.size = 40});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(quoteDiscountApprovalsBadgeProvider).valueOrNull ?? 0;
    final label = discountApprovalsLabel(n);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.r),
          child: SizedBox(
            width: size.w,
            height: size.w,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              Icon(PhosphorIconsRegular.sealCheck, size: 22.sp, color: AppColors.navy),
              if (n > 0)
                Positioned(
                  top: 2.h,
                  right: 2.w,
                  child: Container(
                    constraints: BoxConstraints(minWidth: 17.w),
                    height: 17.w,
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.white, width: 1.5),
                    ),
                    child: Text('$n', style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
