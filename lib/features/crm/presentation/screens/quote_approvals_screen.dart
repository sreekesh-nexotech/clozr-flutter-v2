import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../application/providers/quote_discount_approvals_providers.dart';
import '../../application/quote_discount_approval_rules.dart';
import '../components/crm_async.dart';
import '../components/due_date_change.dart' show dueDateLabel;
import '../components/quote_discount_approval.dart' show showDiscountDecisionDialog;

/// Webapp `DiscountApprovalsScreen` (Quotes › Discount approvals), as cards:
/// Pending / Approved / Rejected requests for quotes whose discount is above
/// the creator's limit. Approve / Reject only where the server says
/// `can_decide`; a tap opens the quote.
class QuoteApprovalsScreen extends ConsumerStatefulWidget {
  const QuoteApprovalsScreen({super.key});

  @override
  ConsumerState<QuoteApprovalsScreen> createState() => _QuoteApprovalsScreenState();
}

const _tabs = [('pending', 'Pending'), ('approved', 'Approved'), ('rejected', 'Rejected')];

class _QuoteApprovalsScreenState extends ConsumerState<QuoteApprovalsScreen> {
  String _status = 'pending';
  int _pageSize = 20;

  ({String status, int pageSize}) get _query => (status: _status, pageSize: _pageSize);

  void _open(DiscountApproval r) {
    if (r.quotationNumber.isEmpty) return;
    context.push('${Routes.quoteDetail}?id=${Uri.encodeQueryComponent(r.quotationNumber)}');
  }

  Future<void> _decide(DiscountApproval r, bool approve) => showDiscountDecisionDialog(
        context,
        ref,
        approve: approve,
        quotationUuid: r.quotationId,
        quoteLabel: r.quotationNumber.isNotEmpty ? r.quotationNumber : r.quotationTitle,
        discountPct: r.discountPct,
        limitPct: r.limitPct,
        inboxQuotationNumber: r.quotationNumber,
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(quoteDiscountApprovalsProvider(_query));
    return Container(
      color: AppColors.bgDetail,
      child: Column(children: [
        DetailAppBar(section: 'Quotes', name: 'Discount approvals', onBack: () => context.pop()),
        SizedBox(
          height: 52.h,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
            children: [
              for (final (key, label) in _tabs) ...[
                TabChip(
                  label: label,
                  active: _status == key,
                  onTap: () => setState(() {
                    _status = key;
                    _pageSize = 20;
                  }),
                ),
                SizedBox(width: 8.w),
              ],
            ],
          ),
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const ListSkeleton(itemCount: 3),
            error: (e, _) => ErrorState.forError(crmAppError(e),
                onRetry: () => ref.invalidate(quoteDiscountApprovalsProvider(_query))),
            data: (page) {
              if (page.rows.isEmpty) {
                final empty = discountApprovalsEmpty(_status);
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(quoteDiscountApprovalsProvider(_query)),
                  child: ListView(children: [
                    EmptyState(icon: PhosphorIconsRegular.sealCheck, title: empty.title, body: empty.body ?? ''),
                  ]),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(quoteDiscountApprovalsProvider(_query));
                  ref.invalidate(quoteDiscountApprovalsBadgeProvider);
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                  children: [
                    for (final r in page.rows) _card(r),
                    if (page.count > page.rows.length)
                      TextButton(
                        onPressed: () => setState(() => _pageSize = _pageSize >= 50 ? 100 : 50),
                        child: Text('Showing ${page.rows.length} of ${page.count} — show more'),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  ({Color fg, Color bg}) _tone(String status) => switch (status) {
        'pending' => (fg: AppColors.warningDeep, bg: AppColors.tintAmber),
        'approved' => (fg: AppColors.success, bg: AppColors.tintGreen),
        'rejected' => (fg: AppColors.error, bg: AppColors.tintRed),
        _ => (fg: AppColors.textMuted, bg: AppColors.bgChipGrey),
      };

  Widget _card(DiscountApproval r) {
    final tone = _tone(r.status);
    final review = r.reviewLine;
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: ClozrCard(
        radius: 16,
        onTap: () => _open(r),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.headline.isEmpty ? '—' : r.headline,
                    style: AppText.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (r.quotationNumber.isNotEmpty) Text(r.quotationNumber, style: AppText.caption()),
              ]),
            ),
            SizedBox(width: 10.w),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(pctLabel(r.discountPct), style: AppText.bodyStrong(color: AppColors.navy)),
              if (r.limitPct != null) Text('Limit ${pctLabel(r.limitPct)}', style: AppText.caption()),
            ]),
          ]),
          SizedBox(height: 8.h),
          Row(children: [
            Expanded(
              child: Text(
                [
                  r.requestedByName.isEmpty ? '—' : r.requestedByName,
                  if (r.requestedAt.isNotEmpty) dueDateLabel(r.requestedAt),
                ].join(' · '),
                style: AppText.caption(),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
              decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(99)),
              child: Text(r.statusLabel, style: AppText.captionStrong(color: tone.fg)),
            ),
          ]),
          if (review.isNotEmpty) ...[
            SizedBox(height: 6.h),
            Text(review, style: AppText.body(color: AppColors.textMuted)),
          ],
          if (r.showDecide) ...[
            SizedBox(height: 10.h),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton.icon(
                onPressed: () => _decide(r, false),
                icon: Icon(PhosphorIconsRegular.x, size: 14.sp),
                label: const Text('Reject'),
              ),
              SizedBox(width: 10.w),
              FilledButton.icon(
                onPressed: () => _decide(r, true),
                icon: Icon(PhosphorIconsRegular.check, size: 14.sp),
                label: const Text('Approve'),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
