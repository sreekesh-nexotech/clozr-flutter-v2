import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../application/approval_rules.dart';
import '../../application/providers/approvals_providers.dart';
import '../../domain/entities/approval.dart';
import '../components/approval_decision_dialog.dart';
import '../components/approval_parts.dart';

/// One request: what changes, who decides, the timeline, and whatever this
/// viewer may do about it (webapp `ApprovalDetailDrawer`, as a pushed screen —
/// route map decision D2). Every button follows the server's `can_*` flags.
class ApprovalDetailScreen extends ConsumerWidget {
  const ApprovalDetailScreen({super.key, required this.approvalId});

  final String approvalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(approvalDetailProvider(approvalId));
    final detail = async.valueOrNull;
    return Container(
      color: AppColors.bgDetail,
      child: Column(children: [
        DetailAppBar(
          section: 'Approval',
          name: detail == null || detail.approval.recordLabel.isEmpty
              ? null
              : detail.approval.recordLabel,
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const ListSkeleton(itemCount: 3),
            error: (e, _) => ErrorState.forError(
                e is AppError
                    ? e
                    : const AppError(
                        type: AppErrorType.unknown,
                        message: 'Something went wrong. Please try again.'),
                onRetry: () =>
                    ref.invalidate(approvalDetailProvider(approvalId))),
            data: (d) => _Body(detail: d),
          ),
        ),
        if (detail != null) _Footer(detail: detail),
      ]),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = detail.approval;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(approvalDetailProvider(a.id)),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
        children: [
          ClozrCard(
            radius: 16,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ApprovalStatusChip(status: a.status),
                SizedBox(width: 10.w),
                Icon(approvalKindIcon(a.kind),
                    size: 14.sp, color: AppColors.textMuted),
                SizedBox(width: 4.w),
                Expanded(
                  child: Text(moduleKindLine(a.module, a.kind),
                      style: AppText.caption()),
                ),
              ]),
              SizedBox(height: 10.h),
              ApprovalChangeText(
                  from: a.from,
                  to: a.to,
                  style: AppText.body().copyWith(fontSize: 15.sp)),
              if (a.requestNote.isNotEmpty) ...[
                SizedBox(height: 6.h),
                Text('“${a.requestNote}”',
                    style: AppText.body(color: AppColors.textMuted)),
              ],
            ]),
          ),
          SizedBox(height: 12.h),
          _Section(title: 'Request', rows: [
            ('Requested by', a.requestedBy?.name ?? ''),
            ('Record owner', a.recordOwner?.name ?? ''),
            ('Approver', a.currentApprover?.name ?? ''),
            ('Raised', absoluteDateTime(a.createdAt)),
            ('Decided by', a.decidedBy?.name ?? ''),
            (
              'Decided',
              a.decidedAt == null ? '' : absoluteDateTime(a.decidedAt)
            ),
            ('Decision note', a.decisionNote),
            if (a.decisionSource == 'admin_override')
              ('Decided as', 'System Admin override'),
          ]),
          if (detail.summary.isNotEmpty) ...[
            SizedBox(height: 12.h),
            _Section(title: 'Record', rows: [
              for (final (k, v) in detail.summary) (summaryLabel(k), v),
            ]),
          ],
          if (detail.steps.isNotEmpty) ...[
            SizedBox(height: 12.h),
            _Timeline(steps: detail.steps),
          ],
        ],
      ),
    );
  }
}

/// A titled card of label / value rows; blank values are left out.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final r in rows)
        if (r.$2.trim().isNotEmpty) r
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return ClozrCard(
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: AppText.micro().copyWith(letterSpacing: 0.6)),
        SizedBox(height: 8.h),
        for (final (label, value) in shown)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 5.h),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 120.w, child: Text(label, style: AppText.caption())),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: AppText.body(color: AppColors.textPrimary)),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Who held the request, in order, and what each of them did.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});

  final List<ApprovalStep> steps;

  @override
  Widget build(BuildContext context) {
    return ClozrCard(
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TIMELINE', style: AppText.micro().copyWith(letterSpacing: 0.6)),
        SizedBox(height: 10.h),
        for (var i = 0; i < steps.length; i++)
          _step(steps[i], last: i == steps.length - 1),
      ]),
    );
  }

  Widget _step(ApprovalStep s, {required bool last}) {
    final open = s.outcome.isEmpty;
    final outcome = stepOutcomeLabels[s.outcome] ?? 'Waiting';
    final reason = routeReasonLabels[s.reason] ?? '';
    final when = absoluteDateTime(s.actedAt ?? s.assignedAt);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Container(
            width: 10.w,
            height: 10.w,
            margin: EdgeInsets.only(top: 4.h),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: open ? AppColors.warningDeep : AppColors.navy,
            ),
          ),
          if (!last)
            Expanded(
                child: Container(width: 1.5, color: AppColors.borderCardSoft)),
        ]),
        SizedBox(width: 10.w),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 14.h),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(style: AppText.body(), children: [
                TextSpan(
                    text: s.approver?.name ?? 'Someone',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                TextSpan(text: ' · $outcome'),
              ])),
              Text(
                  [if (reason.isNotEmpty) reason, if (when.isNotEmpty) when]
                      .join(' · '),
                  style: AppText.caption()),
              if (s.note.isNotEmpty)
                Text('“${s.note}”',
                    style: AppText.body(color: AppColors.textMuted)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Open record / Withdraw / Escalate on one row, Reject / Approve below —
/// only those this viewer may use while the request is pending.
class _Footer extends ConsumerWidget {
  const _Footer({required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = detail.approval;
    final pending = a.isPending;
    final path =
        detail.recordVisible ? approvalRecordPath(a.module, a.objectId) : null;
    final canWithdraw = pending && detail.canWithdraw;
    final canEscalate = pending && detail.canEscalate;
    final canDecide = pending && a.canDecide;
    if (path == null && !canWithdraw && !canEscalate && !canDecide) {
      return const SizedBox.shrink();
    }

    Future<void> decide(ApprovalAction action) async {
      final ok = await showApprovalDecisionDialog(context, ref,
          action: action,
          approvalId: a.id,
          module: a.module,
          objectId: a.objectId,
          subject: a.recordLabel.isEmpty ? 'this request' : a.recordLabel,
          change: changeLabel(a.from, a.to));
      if (ok && context.mounted && context.canPop()) context.pop();
    }

    Future<void> withdraw() async {
      final ok = await withdrawApproval(ref,
          approvalId: a.id, module: a.module, objectId: a.objectId);
      if (ok && context.mounted && context.canPop()) context.pop();
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (path != null || canWithdraw || canEscalate)
          Row(children: [
            if (path != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(path),
                  icon: Icon(PhosphorIconsRegular.eye, size: 14.sp),
                  label: const Text('Open record'),
                ),
              ),
            if (canWithdraw) ...[
              if (path != null) SizedBox(width: 10.w),
              Expanded(
                child: OutlinedButton(
                    onPressed: withdraw, child: const Text('Withdraw')),
              ),
            ],
            if (canEscalate) ...[
              if (path != null || canWithdraw) SizedBox(width: 10.w),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => decide(ApprovalAction.escalate),
                  icon: Icon(PhosphorIconsRegular.arrowUp, size: 14.sp),
                  label: const Text('Escalate'),
                ),
              ),
            ],
          ]),
        if (canDecide) ...[
          if (path != null || canWithdraw || canEscalate)
            SizedBox(height: 10.h),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => decide(ApprovalAction.reject),
                icon: Icon(PhosphorIconsRegular.x, size: 14.sp),
                label: const Text('Reject'),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => decide(ApprovalAction.approve),
                icon: Icon(PhosphorIconsRegular.check, size: 14.sp),
                label: const Text('Approve'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
