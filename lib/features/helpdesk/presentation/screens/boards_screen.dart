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
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/ticket_query.dart';
import '../../application/providers/tickets_providers.dart';
import '../../../../data/api/user_directory.dart';
import '../../domain/entities/issue_summary.dart';
import '../../domain/entities/ticket.dart';
import '../components/board_row.dart';
import '../util/ticket_sla.dart';

/// Support Overview — a read-only SLA monitoring board: a live-ish header with a
/// refresh chip, a 4-up stat strip, and four collapsible SLA-watch sections.
class BoardsScreen extends ConsumerStatefulWidget {
  const BoardsScreen({super.key});

  @override
  ConsumerState<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends ConsumerState<BoardsScreen> {
  /// When the board's data was last loaded. Null until the first rows land.
  ///
  /// This was a hardcoded "Updated 30s ago" string: the board claimed a
  /// freshness it had no way of knowing, and the figure never changed.
  DateTime? _loadedAt;

  String get _updatedLabel {
    final at = _loadedAt;
    if (at == null) return 'Updating…';
    final secs = DateTime.now().difference(at).inSeconds;
    if (secs < 45) return 'Updated just now';
    final mins = (secs / 60).round();
    if (mins < 60) return 'Updated ${mins}m ago';
    return 'Updated ${(mins / 60).round()}h ago';
  }

  static const _sections = [
    ('breached', 'Breached'),
    ('lt1h', 'Due < 1h'),
    ('today', 'Due today'),
    ('ontrack', 'On track'),
  ];

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(ticketsProvider);
    final tickets = ticketsAsync.valueOrNull ?? const [];
    // Stamped when rows first arrive, so the header reports a real load time.
    if (ticketsAsync.hasValue && _loadedAt == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loadedAt = DateTime.now());
      });
    }
    final expanded = ref.watch(boardExpandedProvider);
    // The server's own Support Overview (helpdesk.md §7). Its SLA arithmetic is
    // pause-aware — a ticket parked On Hold does not drift toward "breached"
    // while frozen — which the client cannot reproduce from a list row.
    final summary = ref.watch(boardSummaryProvider).valueOrNull;

    final buckets = <String, List<Ticket>>{'breached': [], 'lt1h': [], 'today': [], 'ontrack': []};
    if (summary != null) {
      buckets['breached'] = _cards(summary.breached);
      buckets['lt1h'] = _cards(summary.dueWithin);
      buckets['today'] = _cards(summary.dueTodayBucket);
      buckets['ontrack'] = _cards(summary.onTrack);
    } else {
      for (final t in tickets) {
        final st = boardState(t);
        if (st != null) buckets[st]!.add(t);
      }
      // Sort each bucket by due proximity (soonest first).
      for (final k in buckets.keys) {
        buckets[k]!.sort((a, b) => _due(a).compareTo(_due(b)));
      }
    }

    // Bucket `items` are capped at 8 while `total` is not, so the counts come
    // from the totals — never from the rows on screen.
    final totals = <String, int>{
      'breached': summary?.slaBreached ?? buckets['breached']!.length,
      'lt1h': summary?.slaDueWithin ?? buckets['lt1h']!.length,
      'today': summary?.slaDueToday ?? buckets['today']!.length,
      'ontrack': summary?.slaOnTrack ?? buckets['ontrack']!.length,
    };

    final open = summary?.open ?? buckets.values.fold<int>(0, (a, b) => a + b.length);
    // Resolved *today*, by the device clock. This matched the literal string
    // '09 Jul' against the display date, so the counter was pinned to the
    // prototype's frozen day — zero on every real day, and wrong on that one
    // in any year but 2026. `resolvedISO` is the instant the API sent.
    final now = DateTime.now();
    final closedToday = summary?.closedToday ??
        tickets.where((t) {
          final done = DateTime.tryParse(t.resolvedISO ?? '')?.toLocal();
          return done != null &&
              done.year == now.year &&
              done.month == now.month &&
              done.day == now.day;
        }).length;

    return Column(
      children: [
        _header(open, totals, closedToday),
        Expanded(
          child: AsyncStateView<List<Ticket>>(
            value: ticketsAsync,
            onRetry: () => refreshTickets(ref),
            onRefresh: () async {
              refreshTickets(ref);
              ref.invalidate(boardSummaryProvider);
              await settle([
                ref.read(ticketsProvider.future),
                ref.read(boardSummaryProvider.future),
              ]);
            },
            data: (_) => ListView(
              // So the gesture still works when the content is short enough
              // to fit the viewport without scrolling.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(2.w, 2.h, 2.w, 10.h),
                  child: Text('SLA WATCH',
                      style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.8)),
                ),
                for (final (key, name) in _sections)
                  _sectionCard(key, name, buckets[key]!, totals[key]!, expanded[key] ?? false),
                if (summary != null) ...[
                  SizedBox(height: 4.h),
                  _workloadCard(summary),
                  SizedBox(height: 12.h),
                  _pipelineCard(summary),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// "+N more" opens the Tickets list showing **that section**, not the list's
  /// last state.
  ///
  /// It used to `go(Routes.tickets)` bare, which lands on whatever was applied
  /// there before — with "My Tickets" on by default, so tapping "+7 more" under
  /// Breached could open a list containing none of those seven. The board is an
  /// org-wide SLA view, so the header toggles that would contradict it are
  /// cleared and the same SLA facet is applied: `sla_breached=true` server-side
  /// for Breached, the clock-based matcher for the other three (`helpdesk.md`
  /// §SLA — only the stored flag has a param).
  // ── Workload (helpdesk.md §7 `workload`) ──
  /// Open tickets nobody is on, then the load per agent. Both are
  /// permission-scoped and computed server-side.
  Widget _workloadCard(IssueSummary s) {
    final rows = s.byAgent;
    return _statCard(
      title: 'Workload',
      subtitle: 'Open tickets by assignee',
      children: [
        // Not tappable: the issues list has **no unassigned filter**.
        // `assigned_to__isnull`, `unassigned` and `assigned_to_isnull` are all
        // silently ignored (verified — each returns the unfiltered count), so a
        // tap could only open a list that is not what the row says.
        _totalRow(
          'Unassigned',
          s.unassigned.total,
          // The one row worth flagging: nobody is working these.
          danger: s.unassigned.total > 0,
        ),
        if (rows.isEmpty)
          _emptyLine('Nothing assigned right now.')
        else
          for (final a in rows)
            _totalRow(a.name, a.total,
                onTap: () => _openFiltered(
                    'assignees', UserDirectory.mapUserId(a.id))),
      ],
    );
  }

  // ── Pipeline (helpdesk.md §7 `pipeline`) ──
  /// Totals per status, keyed by the org's own `IssueStatus` rows — never a
  /// fixed set of columns.
  Widget _pipelineCard(IssueSummary s) {
    return _statCard(
      title: 'Pipeline',
      subtitle: 'Tickets by status',
      children: [
        if (s.pipeline.isEmpty)
          _emptyLine('No statuses to show.')
        else
          for (final p in s.pipeline)
            // The drawer's Status facet is keyed by `issue_status_id`, which is
            // exactly what `pipeline` carries.
            _totalRow(p.name, p.total, onTap: () => _openFiltered('statuses', p.id)),
      ],
    );
  }

  Widget _statCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text(subtitle,
              style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          SizedBox(height: 6.h),
          ...children,
        ],
      ),
    );
  }

  Widget _totalRow(String label, int total, {bool danger = false, VoidCallback? onTap}) {
    final row = Container(
      padding: EdgeInsets.symmetric(vertical: 11.h),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: danger ? AppColors.error : AppColors.textPrimary)),
          ),
          SizedBox(width: 10.w),
          Text('$total',
              style: AppText.custom(
                  size: 13.5,
                  weight: FontWeight.w800,
                  color: danger ? AppColors.error : AppColors.textLabelAlt)),
          if (onTap != null) ...[
            SizedBox(width: 6.w),
            Icon(PhosphorIconsBold.caretRight, size: 12.sp, color: AppColors.textPlaceholder),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }

  /// Opens the Tickets list showing exactly this row.
  ///
  /// Same reset as [_openSection]: the board is an org-wide view, so the header
  /// toggles that would contradict it ("My Tickets" defaults on) are cleared
  /// before the facet is applied.
  void _openFiltered(String field, String optionId) {
    if (optionId.isEmpty) return;
    ref.read(ticketFiltersProvider.notifier).state = FilterValues()
      ..[field] = ChoiceValue(ids: {optionId});
    ref.read(ticketMineProvider.notifier).state = false;
    ref.read(ticketBreachingProvider.notifier).state = false;
    ref.read(ticketTabProvider.notifier).state = 'all';
    ref.read(ticketSearchProvider.notifier).state = '';
    context.go(Routes.tickets);
  }

  Widget _emptyLine(String text) => Container(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
        child: Text(text,
            style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
      );

  /// A bucket's cards as [Ticket]s, so the existing row and pill render them.
  ///
  /// `sla_remaining_seconds` becomes the effective deadline: it is signed and
  /// already has hold time subtracted, so the pill reads the server's verdict
  /// rather than recomputing one.
  List<Ticket> _cards(SlaBucket bucket) => [
        for (final c in bucket.items)
          Ticket(
            id: c.id,
            reference: c.reference,
            subject: c.subject,
            cat: '',
            custId: '',
            contact: '',
            channel: '',
            // Forced open, not folded from `status_name`: the bucket is the
            // server's verdict, and a card whose status folds outside
            // new/open would otherwise render "Due 12 Aug" under Breached.
            status: 'open',
            statusName: c.statusName,
            pri: c.priority,
            assignees: [
              if (UserDirectory.mapUserId(c.assigneeId) case final id
                  when id.isNotEmpty)
                id,
            ],
            product: null,
            projId: null,
            taskId: null,
            created: '',
            responded: null,
            resolved: null,
            respByISO: null,
            respByLabel: null,
            resolveByISO: c.dueAt?.toIso8601String(),
            resolveByLabel: null,
            desc: '',
          ),
      ];

  void _openSection(String key) {
    final facet = ticketSlaFacetForBoard(key);
    if (facet == null) return;
    final values = FilterValues()
      ..['sla'] = RadioValue(id: facet, defaultId: 'any');
    ref.read(ticketFiltersProvider.notifier).state = values;
    ref.read(ticketMineProvider.notifier).state = false;
    ref.read(ticketBreachingProvider.notifier).state = false;
    ref.read(ticketTabProvider.notifier).state = 'all';
    ref.read(ticketSearchProvider.notifier).state = '';
    context.go(Routes.tickets);
  }

  int _due(Ticket t) {
    final iso = (t.responded == null && t.respByISO != null) ? t.respByISO : t.resolveByISO;
    return iso == null ? 1 << 62 : DateTime.parse(iso).millisecondsSinceEpoch;
  }

  Widget _header(int open, Map<String, int> totals, int closedToday) {
    final stats = <(String, String, Color)>[
      ('Open', '$open', AppColors.textPrimary),
      ('Breached', '${totals['breached']}', AppColors.error),
      ('Due today', '${totals['lt1h']! + totals['today']!}', AppColors.textPrimary),
      ('Closed today', '$closedToday', AppColors.textPrimary),
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Helpdesk', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 1.h),
                    Text('Support Overview', style: AppText.screenTitle()),
                  ],
                ),
              ),
              GestureDetector(
                // Actually refetches. This used to relabel itself and toast
                // "Board refreshed just now" without making a single request.
                onTap: () async {
                  refreshTickets(ref);
                  await settle([ref.read(ticketsProvider.future)]);
                  if (!mounted) return;
                  setState(() => _loadedAt = DateTime.now());
                  ref.read(toastProvider.notifier).show('Board refreshed');
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: AppColors.borderChip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.arrowsClockwise, size: 14.sp, color: AppColors.textMuted),
                      SizedBox(width: 6.w),
                      Text(_updatedLabel, style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Container(
            padding: EdgeInsets.symmetric(vertical: 11.h),
            decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(13.r)),
            child: Row(
              children: [
                for (int i = 0; i < stats.length; i++)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.borderChip)),
                      ),
                      child: Column(
                        children: [
                          Text(stats[i].$2, style: AppText.custom(size: 19, weight: FontWeight.w800, color: stats[i].$3, letterSpacing: -0.4)),
                          SizedBox(height: 1.h),
                          Text(stats[i].$1, style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String key, String name, List<Ticket> rows, int total, bool expanded) {
    final isBreached = key == 'breached';
    // `total` is the server's uncapped count; `rows` is capped at 8 by the API.
    final shown = rows.take(8).toList();
    final moreCount = total - shown.length;
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.borderCardSoft),
        boxShadow: [
          BoxShadow(color: const Color(0xFF101828).withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: const Color(0xFF101828).withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final next = Map<String, bool>.from(ref.read(boardExpandedProvider));
              next[key] = !expanded;
              ref.read(boardExpandedProvider.notifier).state = next;
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              child: Row(
                children: [
                  Text(name, style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(width: 9.w),
                  Container(
                    constraints: BoxConstraints(minWidth: 24.w),
                    height: 22.h,
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(horizontal: 7.w),
                    decoration: BoxDecoration(
                      color: isBreached ? AppColors.tintRed : AppColors.bgChipGrey,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text('$total',
                        style: AppText.custom(size: 12, weight: FontWeight.w800, color: isBreached ? AppColors.error : AppColors.textLabelAlt)),
                  ),
                  if (isBreached) ...[
                    SizedBox(width: 9.w),
                    Text('▲1 today', style: AppText.custom(size: 11, weight: FontWeight.w800, color: AppColors.error)),
                  ],
                  const Spacer(),
                  Icon(expanded ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 13.sp, color: AppColors.textPlaceholder),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
              child: Column(
                children: [
                  if (rows.isEmpty)
                    Container(
                      padding: EdgeInsets.only(top: 18.h, bottom: 14.h),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIconsRegular.checkCircle, size: 15.sp, color: AppColors.tealLight),
                          SizedBox(width: 7.w),
                          Text('Nothing breaching soon',
                              style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.tealLight)),
                        ],
                      ),
                    )
                  else ...[
                    for (final t in shown)
                      BoardRow(
                        ticket: t,
                        onTap: () => context.push('${Routes.ticketDetail}?id=${t.id}&from=board'),
                      ),
                    if (moreCount > 0)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openSection(key),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('+$moreCount more', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.blueBright)),
                              SizedBox(width: 6.w),
                              Icon(PhosphorIconsBold.arrowRight, size: 12.sp, color: AppColors.blueBright),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
