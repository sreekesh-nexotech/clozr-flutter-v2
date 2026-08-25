import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../application/providers/help_dashboard_providers.dart';
import '../../application/providers/tickets_providers.dart';
import '../../domain/entities/help_dashboard.dart';
import '../../domain/entities/ticket.dart';
import '../components/donut_chart.dart';
import '../util/ticket_sla.dart';

/// Helpdesk Home — the staff dashboard: a KPI 2×2 grid, stacked SLA-status and
/// priority-mix donuts with legends, crossed-SLA and needing-attention lists,
/// and a resolved-by-priority matrix.
class HelpHomeScreen extends ConsumerWidget {
  const HelpHomeScreen({super.key});

  int _homeDue(Ticket t) {
    final resp = (t.respByISO != null && t.responded == null) ? DateTime.parse(t.respByISO!).millisecondsSinceEpoch : (1 << 62);
    final res = t.resolveByISO != null ? DateTime.parse(t.resolveByISO!).millisecondsSinceEpoch : (1 << 62);
    return resp < res ? resp : res;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsProvider);
    final slaVal = ref.watch(helpSlaValProvider);

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 16.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Helpdesk', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                      SizedBox(height: 1.h),
                      Text('Dashboard', style: AppText.screenTitle()),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: 3.h),
                  // Today, from the device clock. This was the literal string
                  // "Thu, 9 Jul" — the prototype's frozen date, which read as
                  // stale on every other day of the year.
                  child: Text(DateFormat('EEE, d MMM').format(DateTime.now()),
                      style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ),
              ],
            ),
            SizedBox(height: 12.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<Ticket>>(
            value: ticketsAsync,
            onRetry: () => refreshTickets(ref),
            onRefresh: () => _refresh(ref),
            data: (tickets) {
              final dir = ref.watch(ticketDirectoryProvider);
              final summary = ref.watch(myTicketSummaryProvider).valueOrNull;
              final mineAll = tickets.where((t) => t.isMine).toList();
              final openT = mineAll.where((t) => t.status == 'new' || t.status == 'open' || t.status == 'pending').toList();
              final doneMine = mineAll.where((t) => t.status == 'resolved' || t.status == 'closed').toList();
              final breached = openT.where((t) => homeState(t) == 'breached').toList()..sort((a, b) => _homeDue(b).compareTo(_homeDue(a)));
              final risk = openT.where((t) => homeState(t) == 'risk').toList();
              final withinOpen = openT.where((t) => homeState(t) == 'within').length;

              final attn = openT.where((t) => homeState(t) != 'within' || t.status == 'pending').toList()
                ..sort((a, b) {
                  final ra = homeState(a) == 'breached' ? 0 : 1;
                  final rb = homeState(b) == 'breached' ? 0 : 1;
                  return ra != rb ? ra - rb : _homeDue(a).compareTo(_homeDue(b));
                });

              return ListView(
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                children: [
                  // The server's own figures where it has them: its counts are
                  // scoped by `assigned_to_me` rather than by `isMine` over a
                  // loaded page, and its SLA arithmetic is pause-aware.
                  _kpiGrid(context, ref, summary?.open ?? openT.length,
                      summary?.breachedNow ?? breached.length),
                  SizedBox(height: 16.h),
                  _slaMixCard(
                    ref,
                    summary?.withinSla ?? (withinOpen + doneMine.length),
                    summary == null ? doneMine.length : 0,
                    summary?.slaDueWithin ?? risk.length,
                    summary?.slaBreached ?? breached.length,
                    mineAll,
                  ),
                  SizedBox(height: 16.h),
                  _crossedCard(context, ref, breached, slaVal, dir),
                  SizedBox(height: 16.h),
                  _attentionCard(context, attn, dir),
                  SizedBox(height: 16.h),
                  _resolvedGrid(context, ref, doneMine),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Pull-to-refresh: the tickets behind every card, plus the server's KPI
  /// figures (the medians and trends have no local fallback).
  Future<void> _refresh(WidgetRef ref) async {
    refreshTickets(ref);
    ref.invalidate(helpKpisProvider);
    ref.invalidate(myTicketSummaryProvider);
    ref.invalidate(helpSlaMixProvider);
    ref.invalidate(helpCompletedGridProvider);
    await settle([
      ref.read(ticketsProvider.future),
      ref.read(helpKpisProvider.future),
      ref.read(myTicketSummaryProvider.future),
      ref.read(helpSlaMixProvider.future),
      ref.read(helpCompletedGridProvider.future),
    ]);
  }

  // ── KPI grid ──
  Widget _kpiGrid(BuildContext context, WidgetRef ref, int openCount, int breachCount) {
    void goTickets({bool breach = false, String tab = 'all'}) {
      ref.read(ticketMineProvider.notifier).state = true;
      ref.read(ticketBreachingProvider.notifier).state = breach;
      ref.read(ticketTabProvider.notifier).state = tab;
      context.go(Routes.tickets);
    }

    // Counts stay local (the ticket list is already loaded); the trends and the
    // two medians come from the server or not at all — see [helpKpisProvider].
    // They were fixed constants: "3.2 days", "1.4 hours" and four invented
    // trend chips that never moved whatever the tickets did.
    final kpis = ref.watch(helpKpisProvider).valueOrNull;
    final resolution = kpis?.avgResolution;
    final response = kpis?.firstResponse;
    final name = ref.watch(sessionControllerProvider).user?.fullName.trim() ?? '';

    final cards = <Widget>[
      KpiCard(
        icon: PhosphorIconsFill.ticket, iconColor: AppColors.blueBright, iconBg: AppColors.tintBlue,
        value: '$openCount', label: 'My Open Tickets',
        sub: name.isEmpty ? 'Assigned to me' : 'Assigned to $name',
        accent: AppColors.blueBright,
        trend: kpis?.openTickets?.trendLabel,
        trendUp: kpis?.openTickets?.trendUp ?? true,
        onTap: () => goTickets(),
      ),
      KpiCard(
        icon: PhosphorIconsFill.warningCircle, iconColor: AppColors.error, iconBg: AppColors.tintRed,
        value: '$breachCount', label: 'My SLA Breaches', sub: 'Response or resolution', accent: AppColors.error,
        trend: kpis?.slaBreaches?.trendLabel,
        // More breaches is worse, so the pill's colour inverts the arrow.
        trendUp: !(kpis?.slaBreaches?.trendUp ?? true),
        arrowUp: kpis?.slaBreaches?.trendUp ?? false,
        onTap: () => goTickets(breach: true),
      ),
      KpiCard(
        icon: PhosphorIconsFill.timer, iconColor: AppColors.error, iconBg: AppColors.tintRed,
        // Sent in minutes; this card reads in days.
        value: resolution?.days == null ? '—' : _trim(resolution!.days!),
        unit: resolution?.days == null ? null : 'days',
        label: 'My Avg Resolution', sub: 'Median, this period', accent: AppColors.error,
        trend: resolution?.trendLabel,
        // A shorter resolution is better, so falling is the good direction.
        trendUp: !(resolution?.trendUp ?? true),
        arrowUp: resolution?.trendUp ?? false,
        onTap: () => goTickets(tab: 'resolved'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.lightning, iconColor: AppColors.success, iconBg: AppColors.tintGreen,
        // Sent in minutes; this card reads in hours.
        value: response?.hours == null ? '—' : _trim(response!.hours!),
        unit: response?.hours == null ? null : 'hours',
        label: 'My First Response', sub: 'Median, this period', accent: AppColors.success,
        trend: response?.trendLabel,
        trendUp: !(response?.trendUp ?? true),
        arrowUp: response?.trendUp ?? false,
        onTap: () => goTickets(),
      ),
    ];
    return Column(
      children: [
        Row(children: [Expanded(child: cards[0]), SizedBox(width: 12.w), Expanded(child: cards[1])]),
        SizedBox(height: 12.h),
        Row(children: [Expanded(child: cards[2]), SizedBox(width: 12.w), Expanded(child: cards[3])]),
      ],
    );
  }

  // ── SLA status & priority mix ──
  Widget _slaMixCard(WidgetRef ref, int withinOpen, int done, int risk, int breached, List<Ticket> mineAll) {
    // `sla-priority-mix/` (§3) when it answered; the loaded tickets otherwise.
    final mix = ref.watch(helpSlaMixProvider).valueOrNull;

    final within = mix?.withinSla ?? (withinOpen + done);
    final atRisk = mix?.atRisk ?? risk;
    final over = mix?.breached ?? breached;
    final slaParts = [
      DonutSegment(within.toDouble(), AppColors.success),
      DonutSegment(atRisk.toDouble(), AppColors.warning),
      DonutSegment(over.toDouble(), AppColors.error),
    ];
    final slaLegend = [
      ('Within SLA', within, AppColors.success),
      ('At risk', atRisk, AppColors.warning),
      ('Breached', over, AppColors.error),
    ];

    // Keyed by the priorities this API actually has. The first slice counted
    // `'Urgent'`, which is not one of them — so it was permanently 0 while
    // every Critical ticket went uncounted.
    int byPri(String p) => mineAll.where((t) => t.pri == p).length;
    final priCounts = <String, (int, Color)>{
      'Critical': (mix?.critical ?? byPri('Critical'), AppColors.error),
      'High': (mix?.high ?? byPri('High'), AppColors.warning),
      'Medium': (mix?.medium ?? byPri('Medium'), AppColors.blueBright),
      'Low': (mix?.low ?? byPri('Low'), AppColors.textPlaceholder),
    };
    final priParts = [
      for (final e in priCounts.entries) DonutSegment(e.value.$1.toDouble(), e.value.$2),
    ];
    final priLegend = [
      for (final e in priCounts.entries) (e.key, e.value.$1, e.value.$2),
    ];

    return ClozrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SLA Status & Priority Mix', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          // The signed-in user, not the prototype's seed name — this card is
          // "my tickets", so it named the wrong person for everyone but him.
          Text(_mineLabel(ref), style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          SizedBox(height: 16.h),
          Center(child: Text('SLA Status', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary))),
          SizedBox(height: 10.h),
          Center(child: DonutChart(segments: slaParts, size: 148.w)),
          SizedBox(height: 6.h),
          for (final l in slaLegend) _legendRow(l.$1, l.$2, l.$3),
          const ClozrDivider(margin: EdgeInsets.only(top: 14, bottom: 2)),
          SizedBox(height: 12.h),
          Center(child: Text('Priority Mix', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary))),
          SizedBox(height: 10.h),
          Center(child: DonutChart(segments: priParts, size: 148.w)),
          SizedBox(height: 6.h),
          for (final l in priLegend) _legendRow(l.$1, l.$2, l.$3),
        ],
      ),
    );
  }

  Widget _legendRow(String label, int count, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7.h, horizontal: 2.w),
      child: Row(
        children: [
          Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          SizedBox(width: 9.w),
          Expanded(child: Text(label, style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBodyMuted))),
          Text('$count', style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  // ── Crossed SLA ──
  Widget _crossedCard(BuildContext context, WidgetRef ref, List<Ticket> breached, bool slaVal, TicketLookups dir) {
    return ClozrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My Tickets Crossed SLA', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text('Breached targets', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
              _miniSeg(ref, slaVal),
            ],
          ),
          if (breached.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 24.h, bottom: 10.h),
              child: Center(child: Text('No breached tickets right now.', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPlaceholder))),
            )
          else
            for (final t in breached) _crossedRow(context, t, slaVal, dir),
        ],
      ),
    );
  }

  Widget _miniSeg(WidgetRef ref, bool slaVal) {
    Widget seg(String label, bool value) {
      final active = slaVal == value;
      return GestureDetector(
        onTap: () => ref.read(helpSlaValProvider.notifier).state = value,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: active ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7.r),
            boxShadow: active ? [BoxShadow(color: const Color(0xFF101828).withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 1))] : null,
          ),
          child: Text(label, style: AppText.custom(size: 12, weight: FontWeight.w700, color: active ? AppColors.navy : AppColors.textMuted)),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(2.r),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(9.r)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('₹ Value', true), seg('Days', false)]),
    );
  }

  Widget _crossedRow(BuildContext context, Ticket t, bool slaVal, TicketLookups dir) {
    final cust = dir.customer(t.custId);
    final right = slaVal ? (dir.project(t.projId)?.cost ?? '—') : homeOverLabel(t);
    return GestureDetector(
      onTap: () => context.push('${Routes.ticketDetail}?id=${t.id}'),
      child: Container(
        margin: EdgeInsets.only(top: 11.h),
        padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 12.h),
        decoration: BoxDecoration(color: AppColors.tintRed, borderRadius: BorderRadius.circular(12.r)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.displayRef, style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.errorDeep)),
                  SizedBox(height: 2.h),
                  Text(t.subject, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 3.h),
                  Text('${cust?.display ?? '—'} · ${t.contact}', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            Text(right, style: AppText.custom(size: 12.5, weight: FontWeight.w800, color: slaVal ? AppColors.textPrimary : AppColors.error)),
          ],
        ),
      ),
    );
  }

  // ── Needing attention ──
  Widget _attentionCard(BuildContext context, List<Ticket> attn, TicketLookups dir) {
    return ClozrCard(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Tickets Needing Attention', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('Breached, paused & at-risk', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          SizedBox(height: 4.h),
          if (attn.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(child: Text('Nothing needs attention right now.', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPlaceholder))),
            )
          else
            for (final t in attn) _attnRow(context, t, dir),
        ],
      ),
    );
  }

  Widget _attnRow(BuildContext context, Ticket t, TicketLookups dir) {
    final cust = dir.customer(t.custId);
    final breachedNow = homeState(t) == 'breached';
    final slaLabel = breachedNow ? homeOverLabel(t) : 'Respond by ${t.respByLabel ?? t.resolveByLabel ?? '—'}';
    return GestureDetector(
      onTap: () => context.push('${Routes.ticketDetail}?id=${t.id}'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.displayRef, style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
            SizedBox(height: 2.h),
            Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
            SizedBox(height: 2.h),
            Text('${cust?.display ?? '—'} · ${t.contact}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
            SizedBox(height: 8.h),
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(color: breachedNow ? AppColors.tintRed : AppColors.bgChipGrey, borderRadius: BorderRadius.circular(7.r)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(breachedNow ? PhosphorIconsFill.warning : PhosphorIconsRegular.clock, size: 11.sp, color: breachedNow ? AppColors.error : AppColors.textBodyMuted),
                      SizedBox(width: 4.w),
                      Text(slaLabel, style: AppText.custom(size: 11, weight: FontWeight.w800, color: breachedNow ? AppColors.error : AppColors.textBodyMuted)),
                    ],
                  ),
                ),
                const Spacer(),
                StatusPill(label: t.pri, color: ticketPriDotColor(t.pri)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The SLA card's sub-label. Falls back to the bare "My tickets" rather than
  /// a placeholder name when there is no session (mock mode).
  static String _mineLabel(WidgetRef ref) {
    final name = ref.watch(sessionControllerProvider).user?.fullName.trim() ?? '';
    return name.isEmpty ? 'My tickets' : 'My tickets · $name';
  }

  /// "3.2" — and "3" when the figure is whole.
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  // ── Resolved grid ──
  Widget _resolvedGrid(BuildContext context, WidgetRef ref, List<Ticket> doneMine) {
    final grid = ref.watch(helpCompletedGridProvider).valueOrNull;
    void goResolved() {
      ref.read(ticketMineProvider.notifier).state = true;
      ref.read(ticketBreachingProvider.notifier).state = false;
      ref.read(ticketTabProvider.notifier).state = 'resolved';
      context.go(Routes.tickets);
    }

    return ClozrCard(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tickets Resolved Grid', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('By priority, this period', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          SizedBox(height: 14.h),
          Container(
            padding: EdgeInsets.only(bottom: 9.h),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
            child: Row(
              children: [
                Expanded(child: Text('PRIORITY', style: _hdr())),
                SizedBox(width: 82.w, child: Text('WITHIN SLA', textAlign: TextAlign.center, style: _hdr())),
                SizedBox(width: 82.w, child: Text('AFTER BREACH', textAlign: TextAlign.center, style: _hdr())),
              ],
            ),
          ),
          // The server's own grid when it answered (§9), else the loaded
          // tickets — which only ever counted the page in hand.
          for (final pri in kTicketPriorities)
            _gridRow(
              pri,
              _gridCount(grid, doneMine, pri, afterBreach: false),
              _gridCount(grid, doneMine, pri, afterBreach: true),
              goResolved,
            ),
        ],
      ),
    );
  }

  /// One priority's count, preferring the server's row.
  ///
  /// The local fallback splits on whether the ticket beat its resolution SLA;
  /// "after breach" used to be a hard-coded 0, so every resolved ticket read as
  /// on time however late it actually was.
  int _gridCount(List<CompletedGridRow>? grid, List<Ticket> doneMine, String pri,
      {required bool afterBreach}) {
    final row = grid
        ?.where((r) => r.priority.trim().toLowerCase() == pri.toLowerCase())
        .firstOrNull;
    if (row != null) return afterBreach ? row.afterDue : row.beforeDue;
    return doneMine
        .where((t) => t.pri == pri && (t.resolvedAfterBreach == true) == afterBreach)
        .length;
  }

  Widget _gridRow(String pri, int within, int after, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
        child: Row(
          children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: StatusPill(label: pri, color: ticketPriPillColor(pri)))),
            SizedBox(width: 82.w, child: Center(child: _gridBadge('$within', false))),
            SizedBox(width: 82.w, child: Center(child: _gridBadge('$after', true))),
          ],
        ),
      ),
    );
  }

  TextStyle _hdr() => AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.6);

  Widget _gridBadge(String value, bool bad) {
    return Container(
      width: 26.w,
      height: 26.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bad ? AppColors.tintRed : AppColors.tintGreen, shape: BoxShape.circle),
      child: Text(value, style: AppText.custom(size: 12, weight: FontWeight.w800, color: bad ? AppColors.error : AppColors.success)),
    );
  }
}
