import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../data/api/user_directory.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/board_rules.dart';
import '../../application/filters/ticket_query.dart';
import '../../application/providers/tickets_providers.dart';
import '../../domain/entities/issue_summary.dart';
import '../util/ticket_sla.dart';

/// Support Overview — the webapp's `SupportOverviewScreen`: a header with the
/// refresh control ("Refreshing…" / "Up to date"), the stat strip (Open
/// tickets, Breached now, Due today, Closed today) and three read-only panels
/// built from `GET /crm/issues/summary/?due_soon_minutes=60` — SLA Watch
/// (Breached, Due < 60m, Due today, On track, No SLA), Workload (Unassigned,
/// then one column per agent) and Pipeline (one lane per org status). The
/// webapp's side-by-side columns stack vertically here so nothing scrolls
/// sideways on a phone.
class BoardsScreen extends ConsumerStatefulWidget {
  const BoardsScreen({super.key});

  @override
  ConsumerState<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends ConsumerState<BoardsScreen> {
  /// Refetches the summary — the header button and pull-to-refresh.
  Future<void> _reload() async {
    ref.invalidate(boardSummaryProvider);
    await settle([ref.read(boardSummaryProvider.future)]);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(boardSummaryProvider);
    final summary = async.valueOrNull ?? const IssueSummary();
    final failed = async.hasError && !async.isLoading;
    return Column(
      children: [
        _header(summary, refreshing: async.isLoading, failed: failed),
        Expanded(
          child: AsyncStateView<IssueSummary?>(
            value: async,
            onRetry: _reload,
            onRefresh: _reload,
            loading: () => const ListSkeleton(),
            error: (e, retry) => AppRefresh(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [ErrorState.forSubject(e, 'the support overview', onRetry: retry)],
              ),
            ),
            data: (_) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 120.h),
              children: [
                _panel('SLA Watch', slaWatchInfo(hasNoSla: summary.noSla != null), [
                  _bucket('breached', 'Breached', summary.breached, red: true),
                  _bucket('lt1h', boardDueSoonLabel, summary.dueWithin, positiveEmpty: true),
                  _bucket('today', 'Due today', summary.dueTodayBucket),
                  _bucket('ontrack', 'On track', summary.onTrack),
                  if (summary.noSla != null)
                    _bucket('nosla', 'No SLA', summary.noSla!, countOnlyNote: noSlaCountOnlyNote),
                ]),
                SizedBox(height: 14.h),
                _panel('Workload', workloadInfo, [for (final c in summary.workload) _workloadColumn(c)]),
                SizedBox(height: 14.h),
                _panel('Pipeline', pipelineInfo, [
                  for (final lane in summary.lanes)
                    _column(
                      label: lane.name,
                      total: lane.total,
                      cards: lane.items,
                      showAvatar: false,
                      showAge: true,
                      onMore: () => _openTickets(
                        bucketMoreToast(lane.total, lane.name),
                        filters: FilterValues()..['statuses'] = ChoiceValue(ids: {lane.id}),
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Header ──
  Widget _header(IssueSummary s, {required bool refreshing, required bool failed}) {
    // No figures while the board failed to load — old numbers next to an
    // error would read as current.
    String fig(int n) => failed ? '—' : '$n';
    final stats = <(String, String, bool, String?)>[
      ('Open tickets', fig(s.open), false, openTicketsTip),
      ('Breached now', fig(s.breachedNow), s.breachedNow > 0, null),
      ('Due today', fig(s.dueToday), false, null),
      ('Closed today', fig(s.closedToday), false, null),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 56.h, 18.w, 12.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Helpdesk', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
          SizedBox(height: 1.h),
          Text('Support Overview', style: AppText.screenTitle()),
          SizedBox(height: 6.h),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: refreshing ? null : _reload,
            child: Row(children: [
              Icon(PhosphorIconsRegular.arrowsClockwise, size: 14.sp, color: AppColors.textMuted),
              SizedBox(width: 7.w),
              Text(refreshing ? 'Refreshing…' : (failed ? 'Couldn’t refresh' : 'Up to date'),
                  style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
            ]),
          ),
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.symmetric(vertical: 11.h),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(13.r),
              border: Border.all(color: AppColors.borderCardSoft),
            ),
            child: Row(
              children: [
                for (int i = 0; i < stats.length; i++)
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 4.w),
                      decoration: BoxDecoration(
                        border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.borderChip)),
                      ),
                      child: Column(children: [
                        Text(stats[i].$2,
                            style: AppText.custom(
                                size: 19,
                                weight: FontWeight.w800,
                                color: stats[i].$3 ? AppColors.error : AppColors.textPrimary,
                                letterSpacing: -0.4)),
                        SizedBox(height: 1.h),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Flexible(
                            child: Text(stats[i].$1,
                                textAlign: TextAlign.center,
                                style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                          ),
                          if (stats[i].$4 != null) ...[
                            SizedBox(width: 3.w),
                            _infoTip(stats[i].$4!, size: 11),
                          ],
                        ]),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The webapp's hover tip as a tap tooltip.
  Widget _infoTip(String text, {double size = 14}) => Tooltip(
        message: text,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 4),
        child: Padding(
          padding: EdgeInsets.all(2.w),
          child: Icon(PhosphorIconsRegular.info, size: size.sp, color: AppColors.textPlaceholder),
        ),
      );

  // ── Panels ──
  Widget _panel(String title, String info, List<Widget> columns) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 12.h),
            child: Row(children: [
              Text(title, style: AppText.custom(size: 15.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
              SizedBox(width: 6.w),
              _infoTip(info),
            ]),
          ),
          const Divider(height: 1, color: AppColors.bgLight),
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Column(children: [
              for (int i = 0; i < columns.length; i++) ...[
                if (i > 0) SizedBox(height: 10.h),
                columns[i],
              ],
            ]),
          ),
        ],
      ),
    );
  }

  /// One SLA Watch bucket. [key] is the Tickets list's SLA facet for "+N more".
  Widget _bucket(String key, String label, SlaBucket b,
      {bool red = false, bool positiveEmpty = false, String? countOnlyNote}) {
    final countOnly = b.items.isEmpty && b.total > 0;
    return _column(
      label: label,
      total: b.total,
      cards: b.items,
      red: red,
      positiveEmpty: positiveEmpty,
      showAvatar: true,
      showAge: false,
      note: countOnly ? countOnlyNote : null,
      onMore: () {
        final facet = ticketSlaFacetForBoard(key);
        _openTickets(bucketMoreToast(b.total, label),
            filters: facet == null ? FilterValues() : (FilterValues()..['sla'] = RadioValue(id: facet, defaultId: 'any')));
      },
    );
  }

  Widget _workloadColumn(WorkloadColumn c) {
    final mappedId = UserDirectory.mapUserId(c.agentId);
    return _column(
      label: c.isUnassigned ? 'Unassigned' : c.agentName,
      avatar: c.isUnassigned ? null : boardInitials(c.agentName),
      total: c.total,
      amber: c.isUnassigned,
      cards: c.items,
      showAvatar: false,
      showAge: false,
      // The list has no "unassigned" filter, so that column opens the list as
      // the webapp does and says how to narrow it.
      onMore: () => _openTickets(workloadMoreToast(c),
          filters: c.isUnassigned || mappedId.isEmpty
              ? FilterValues()
              : (FilterValues()..['assignees'] = ChoiceValue(ids: {mappedId}))),
    );
  }

  /// A read-only column: header (avatar, label, count pill), the cards or an
  /// empty state, and the "+N more →" / "View in tickets →" footer.
  Widget _column({
    required String label,
    required int total,
    required List<SummaryCard> cards,
    required bool showAvatar,
    required bool showAge,
    required VoidCallback onMore,
    String? avatar,
    bool red = false,
    bool amber = false,
    bool positiveEmpty = false,
    String? note,
  }) {
    final (pillBg, pillFg) = red && total > 0
        ? (AppColors.tintRed, AppColors.error)
        : amber && total > 0
            ? (AppColors.tintAmber, AppColors.warningDeep)
            : (AppColors.bgChipGrey, AppColors.textLabelAlt);
    final more = boardMoreLabel(total, cards.length);
    return Container(
      decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(14.r)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 11.h, 12.w, 6.h),
            child: Row(children: [
              if (avatar != null) ...[
                _avatar(avatar, 22),
                SizedBox(width: 8.w),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textBody)),
              ),
              SizedBox(width: 8.w),
              Container(
                constraints: BoxConstraints(minWidth: 22.w),
                height: 20.h,
                padding: EdgeInsets.symmetric(horizontal: 6.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(99)),
                child: Text('$total', style: AppText.custom(size: 11, weight: FontWeight.w700, color: pillFg)),
              ),
            ]),
          ),
          // A column the server sent as a bare count has nothing to show
          // between its header and "View in tickets →".
          if (total == 0 || note != null || cards.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(10.w, 2.h, 10.w, 10.h),
            child: total == 0
                ? _empty(positiveEmpty)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (note != null)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 4.h),
                        child: Text(note,
                            style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.5)),
                      ),
                    for (int i = 0; i < cards.length; i++) ...[
                      if (i > 0) SizedBox(height: 8.h),
                      _card(cards[i], showAvatar: showAvatar, showAge: showAge),
                    ],
                  ]),
          ),
          if (more != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMore,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
                child: Text(more, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.navy)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(bool positive) {
    if (!positive) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        child: Center(
          child: Text('No tickets', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      child: Column(children: [
        Container(
          width: 34.w,
          height: 34.w,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.tintGreen, shape: BoxShape.circle),
          child: Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.success),
        ),
        SizedBox(height: 8.h),
        Text('Nothing breaching soon', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.success)),
      ]),
    );
  }

  /// The mini card: subject; priority dot, SLA pill, link glyph, age
  /// (Pipeline) and assignee avatar (SLA Watch). Tapping opens the ticket.
  Widget _card(SummaryCard c, {required bool showAvatar, required bool showAge}) {
    final pill = boardCardPill(c);
    final (bg, fg) = switch (pill.tone) {
      BoardPillTone.breached => (AppColors.tintRed, AppColors.error),
      BoardPillTone.atRisk => (AppColors.tintAmber, AppColors.warningDeep),
      _ => (AppColors.bgChipGrey, AppColors.textLabelAlt),
    };
    final age = showAge ? boardCardAge(c.createdAt) : '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.ticketDetail}?id=${c.id}&from=board'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderCardSoft),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
          SizedBox(height: 8.h),
          Row(children: [
            Tooltip(
              message: '${c.priority} priority',
              triggerMode: TooltipTriggerMode.longPress,
              child: Container(
                width: 8.w,
                height: 8.w,
                decoration: BoxDecoration(color: ticketPriorityColor(c.priority), shape: BoxShape.circle),
              ),
            ),
            SizedBox(width: 8.w),
            Container(
              height: 20.h,
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
              child: Text(pill.label, style: AppText.custom(size: 11, weight: FontWeight.w700, color: fg)),
            ),
            if (c.hasLinkedTasks) ...[
              SizedBox(width: 8.w),
              Icon(PhosphorIconsRegular.link, size: 12.sp, color: AppColors.textMuted),
            ],
            const Spacer(),
            if (age.isNotEmpty)
              Text(age, style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
            if (showAvatar) ...[
              if (age.isNotEmpty) SizedBox(width: 8.w),
              _avatar(boardInitials(c.assigneeName), 18),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _avatar(String initials, double size) => Container(
        width: size.w,
        height: size.w,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.tintNavy, shape: BoxShape.circle),
        child: Text(initials,
            style: AppText.custom(size: size * 0.42, weight: FontWeight.w700, color: AppColors.navy)),
      );

  /// Opens the Tickets list narrowed to [filters] (the board is org-wide, so
  /// "My Tickets" and the other header toggles are cleared) with the
  /// webapp's info toast.
  void _openTickets(String toast, {required FilterValues filters}) {
    ref.read(ticketFiltersProvider.notifier).state = filters;
    ref.read(ticketMineProvider.notifier).state = false;
    ref.read(ticketBreachingProvider.notifier).state = false;
    ref.read(ticketStatusChipsProvider.notifier).state = const <String>{};
    ref.read(ticketSavedFiltersProvider.notifier).deactivate();
    ref.read(ticketSearchProvider.notifier).state = '';
    context.go(Routes.tickets);
    ref.read(toastProvider.notifier).showInfo(toast);
  }
}
