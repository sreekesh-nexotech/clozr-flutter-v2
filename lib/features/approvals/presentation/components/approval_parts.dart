import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../auth/application/providers/module_perm_providers.dart';
import '../../application/approval_rules.dart';
import '../../application/providers/approvals_providers.dart';
import '../../domain/entities/approval.dart';
import 'approval_decision_dialog.dart';

/// Status chip colours — the same tones the other approval inboxes use.
({Color fg, Color bg}) approvalStatusTone(String status) => switch (status) {
      ApprovalStatuses.pending => (
          fg: AppColors.warningDeep,
          bg: AppColors.tintAmber
        ),
      ApprovalStatuses.approved => (
          fg: AppColors.success,
          bg: AppColors.tintGreen
        ),
      ApprovalStatuses.rejected => (fg: AppColors.error, bg: AppColors.tintRed),
      _ => (fg: AppColors.textMuted, bg: AppColors.bgChipGrey),
    };

IconData approvalKindIcon(String kind) => switch (kind) {
      ApprovalKinds.close => PhosphorIconsRegular.checkCircle,
      ApprovalKinds.ownerTransfer => PhosphorIconsRegular.arrowsLeftRight,
      ApprovalKinds.dueDate => PhosphorIconsRegular.calendarBlank,
      _ => PhosphorIconsRegular.sealCheck,
    };

/// The rounded status chip.
class ApprovalStatusChip extends StatelessWidget {
  const ApprovalStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tone = approvalStatusTone(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
          color: tone.bg, borderRadius: BorderRadius.circular(99)),
      child: Text(statusLabel(status),
          style: AppText.captionStrong(color: tone.fg)),
    );
  }
}

/// "In progress → **Completed**".
class ApprovalChangeText extends StatelessWidget {
  const ApprovalChangeText(
      {super.key, required this.from, required this.to, this.style});

  final String from;
  final String to;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (from.isEmpty && to.isEmpty) return const SizedBox.shrink();
    return Text.rich(TextSpan(style: style ?? AppText.body(), children: [
      TextSpan(text: '${from.isEmpty ? '—' : from} → '),
      TextSpan(
          text: to.isEmpty ? '—' : to,
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
    ]));
  }
}

/// One request in the Approvals list, in the app's approval-card layout.
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    super.key,
    required this.approval,
    required this.onTap,
    this.selectable = false,
    this.selected = false,
    this.onSelect,
    this.onLongPress,
  });

  final Approval approval;
  final VoidCallback onTap;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool>? onSelect;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final a = approval;
    final requested = [
      a.requestedBy?.name ?? '—',
      if (a.createdAt != null) relativeTime(a.createdAt),
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ClozrCard(
          radius: 16,
          borderColor: selected ? AppColors.navy : AppColors.borderCardSoft,
          onTap: selectable ? () => onSelect?.call(!selected) : onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (selectable) ...[
                SizedBox(
                  width: 24.w,
                  height: 24.w,
                  child: Checkbox(
                    value: selected,
                    onChanged:
                        a.canDecide ? (v) => onSelect?.call(v == true) : null,
                  ),
                ),
                SizedBox(width: 10.w),
              ],
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          a.recordLabel.isEmpty
                              ? 'Untitled record'
                              : a.recordLabel,
                          style: AppText.bodyStrong(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      SizedBox(height: 2.h),
                      Row(children: [
                        Icon(approvalKindIcon(a.kind),
                            size: 13.sp, color: AppColors.textMuted),
                        SizedBox(width: 4.w),
                        Flexible(
                          child: Text(moduleKindLine(a.module, a.kind),
                              style: AppText.caption(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ]),
              ),
              SizedBox(width: 10.w),
              ApprovalStatusChip(status: a.status),
            ]),
            SizedBox(height: 8.h),
            ApprovalChangeText(from: a.from, to: a.to),
            if (a.requestNote.isNotEmpty) ...[
              SizedBox(height: 4.h),
              Text('“${a.requestNote}”',
                  style: AppText.body(color: AppColors.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            SizedBox(height: 8.h),
            Text(requested, style: AppText.caption()),
            if ((a.recordOwner?.name ?? '').isNotEmpty ||
                (a.isPending && a.currentApprover != null))
              Text(
                [
                  if ((a.recordOwner?.name ?? '').isNotEmpty)
                    'Owner: ${a.recordOwner!.name}',
                  if (a.isPending && a.currentApprover != null)
                    'With ${a.currentApprover!.name}',
                ].join(' · '),
                style: AppText.caption(),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The strip on a record page while a request waits on it. The record stays
/// fully workable, so this only says what is held and offers what this viewer
/// may do (the server's `can_*` flags) — webapp `ApprovalBanner`.
class ApprovalBanner extends ConsumerWidget {
  const ApprovalBanner(
      {super.key, required this.module, required this.objectId, this.margin});

  /// An `ApprovalModules` value.
  final String module;

  /// The record's public id.
  final String objectId;

  /// Space around the strip; only applies while it shows. Defaults to the
  /// 14 above that the other record banners use.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (objectId.isEmpty) return const SizedBox.shrink();
    final state = ref
        .watch(recordApprovalProvider((module: module, objectId: objectId)))
        .valueOrNull;
    final p = state?.pending;
    if (p == null) return const SizedBox.shrink();

    Future<void> decide(ApprovalAction action) => showApprovalDecisionDialog(
          context,
          ref,
          action: action,
          approvalId: p.id,
          module: module,
          objectId: objectId,
          change: changeLabel(p.from, p.to),
        );

    return Container(
      width: double.infinity,
      margin: margin ?? EdgeInsets.only(top: 14.h),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: AppColors.tintAmber,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(PhosphorIconsRegular.hourglassMedium,
              size: 16.sp, color: AppColors.warningDeep),
          SizedBox(width: 8.w),
          Expanded(
            child: Text.rich(TextSpan(style: AppText.body(), children: [
              TextSpan(
                  text: pendingHeadline(p, date: absoluteDate),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const TextSpan(text: ' The record stays as it is until then.'),
            ])),
          ),
        ]),
        if (p.canWithdraw || p.canEscalate || p.canDecide) ...[
          SizedBox(height: 10.h),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10.w,
            runSpacing: 8.h,
            children: [
              if (p.canWithdraw)
                OutlinedButton(
                  onPressed: () => withdrawApproval(ref,
                      approvalId: p.id, module: module, objectId: objectId),
                  child: const Text('Withdraw'),
                ),
              if (p.canEscalate)
                OutlinedButton.icon(
                  onPressed: () => decide(ApprovalAction.escalate),
                  icon: Icon(PhosphorIconsRegular.arrowUp, size: 14.sp),
                  label: const Text('Escalate'),
                ),
              if (p.canDecide) ...[
                OutlinedButton.icon(
                  onPressed: () => decide(ApprovalAction.reject),
                  icon: Icon(PhosphorIconsRegular.x, size: 14.sp),
                  label: const Text('Reject'),
                ),
                FilledButton.icon(
                  onPressed: () => decide(ApprovalAction.approve),
                  icon: Icon(PhosphorIconsRegular.check, size: 14.sp),
                  label: const Text('Approve'),
                ),
              ],
            ],
          ),
        ],
      ]),
    );
  }
}

/// "Sent for approval" — on a list / board card once this session sent the
/// record for approval (webapp `PendingApprovalChip`).
class PendingApprovalChip extends ConsumerWidget {
  const PendingApprovalChip(
      {super.key, required this.recordId, this.padding = EdgeInsets.zero});

  final String recordId;

  /// Space around the chip — only taken while it shows, so a card with
  /// nothing waiting keeps its layout.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (recordId.isEmpty || !ref.watch(isRecordHeldProvider(recordId))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: padding,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
        decoration: BoxDecoration(
            color: AppColors.tintAmber,
            borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(PhosphorIconsRegular.hourglassMedium,
              size: 11.sp, color: AppColors.warningDeep),
          SizedBox(width: 4.w),
          Text('Sent for approval',
              style: AppText.captionStrong(color: AppColors.warningDeep)),
        ]),
      ),
    );
  }
}

/// Approvals that keep their own page (webapp `OtherApprovalsStrip`). Only
/// the ones with a mobile screen are linked — rewards and lifecycle stages
/// have none yet, so they stay hidden (route map decision D3).
/// The approvals that live on their own screen — quote discounts — linked
/// from Approvals so every approval type is reachable here (UI/UX audit #23).
/// Shown to anyone with the Quotes module, with the waiting count when any.
class OtherApprovalsStrip extends ConsumerWidget {
  const OtherApprovalsStrip({super.key, required this.counts});

  final ApprovalCounts counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotes = counts.other['quote_discounts'] ?? 0;
    if (quotes <= 0 && !ref.watch(modulePermProvider('quotation')).read) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 4.h),
      child: ClozrCard(
        radius: 14,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        onTap: () => context.push(Routes.quoteApprovals),
        child: Row(children: [
          Icon(PhosphorIconsRegular.receipt,
              size: 18.sp, color: AppColors.navy),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
                quotes > 0
                    ? 'Quote discounts waiting for you'
                    : 'Quote discount approvals',
                style: AppText.bodyStrong()),
          ),
          if (quotes > 0)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
              decoration: BoxDecoration(
                  color: AppColors.tintAmber,
                  borderRadius: BorderRadius.circular(99)),
              child: Text('$quotes',
                  style: AppText.captionStrong(color: AppColors.warningDeep)),
            ),
          SizedBox(width: 6.w),
          Icon(PhosphorIconsBold.caretRight,
              size: 13.sp, color: AppColors.textPlaceholder),
        ]),
      ),
    );
  }
}

/// The red count dot used on navigation entries.
class ApprovalCountDot extends StatelessWidget {
  const ApprovalCountDot({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: BoxConstraints(minWidth: 20.w),
      height: 20.w,
      padding: EdgeInsets.symmetric(horizontal: 6.w),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: AppColors.error, borderRadius: BorderRadius.circular(99)),
      child: Text(count > 99 ? '99+' : '$count',
          style: AppText.custom(
              size: 11, weight: FontWeight.w700, color: AppColors.white)),
    );
  }
}
