import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/config/constants.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/inr_format.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/sparkline.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/crm_home_models.dart';
import '../../application/providers/crm_home_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';

/// CRM Home dashboard — KPI grid, lead funnel, first-response trend, attention
/// grid, recent wins and an overdue-items module (design lines 48–207).
///
/// In **mock mode** (`ApiConfig.apiEnabled == false`) the screen renders the
/// const literals below unchanged. In **API mode** it is backed by the personal
/// `dashboard-crm/*` endpoints via [crmHomeProvider]: loading → skeleton,
/// failure → an [ErrorState] with Retry, and data → the real figures (a missing
/// or empty section renders an empty/zero state, never the const literals).
class CrmHomeScreen extends ConsumerWidget {
  const CrmHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: ApiConfig.apiEnabled ? _apiBody(context, ref) : _mockList(context, ref),
        ),
      ],
    );
  }

  /// Pull-to-refresh: the dashboard aggregate plus the three lists its cards
  /// link into, so the counts and the lists they open cannot disagree.
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(crmHomeProvider);
    ref.invalidate(leadsScopedProvider);
    ref.invalidate(crmTasksProvider);
    refreshFollowups(ref);
    await settle([
      ref.read(crmHomeProvider.future),
      ref.read(leadsProvider.future),
      ref.read(crmTasksProvider.future),
      ref.read(followupsProvider.future),
    ]);
  }

  // ── Mock body (byte-identical to the presentation build) ──
  Widget _mockList(BuildContext context, WidgetRef ref) {
    return AppRefresh(
      onRefresh: () => _refresh(ref),
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
      children: [
        _kpiGrid(context, ref),
        SizedBox(height: 16.h),
        _funnelCard(context, ref),
        SizedBox(height: 16.h),
        _responseTrendCard(),
        SizedBox(height: 22.h),
        _sectionHeading(PhosphorIconsFill.warningCircle, AppColors.warning, 'Attention needed'),
        SizedBox(height: 11.h),
        _attentionGrid(context, ref),
        SizedBox(height: 16.h),
        _winsCard(context, wins: crmRecentWins, countLabel: crmWinsCount, totalLabel: crmWinsTotal),
        SizedBox(height: 16.h),
        _overdueCard(context, ref, data: crmOverdueData),
      ],
      ),
    );
  }

  // ── API body: loading → skeleton, error → ErrorState, data → real figures ──
  Widget _apiBody(BuildContext context, WidgetRef ref) {
    final async = ref.watch(crmHomeProvider);
    return async.when(
      loading: () => const ListSkeleton(),
      error: (e, _) {
        final err = e is AppError
            ? e
            : const AppError(
                type: AppErrorType.unknown, message: 'Something went wrong. Please try again.');
        return ListView(
          children: [
            ErrorState.forError(err, onRetry: () => ref.invalidate(crmHomeProvider)),
          ],
        );
      },
      data: (d) => AppRefresh(
        onRefresh: () => _refresh(ref),
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
        children: [
          _apiKpiGrid(context, ref, d.kpis),
          SizedBox(height: 16.h),
          _apiFunnelCard(context, ref, d.funnel),
          SizedBox(height: 16.h),
          _apiResponseTrendCard(d.firstResponseMedianMinutes),
          SizedBox(height: 22.h),
          _sectionHeading(PhosphorIconsFill.warningCircle, AppColors.warning, 'Attention needed'),
          SizedBox(height: 11.h),
          _apiAttentionGrid(context, ref, d.attention),
          SizedBox(height: 16.h),
          _winsCard(
            context,
            wins: d.wins,
            countLabel: '${d.winsCount} ${d.winsCount == 1 ? 'deal' : 'deals'} won',
            totalLabel: '${formatInr(d.winsTotal)} total value',
          ),
          SizedBox(height: 16.h),
          _overdueCard(context, ref, data: d.overdue),
        ],
        ),
      ),
    );
  }

  // ── Header ──
  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      padding: EdgeInsets.fromLTRB(18.w, 56.h, 18.w, 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
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
                    Text('CRM', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 1.h),
                    Text('Dashboard', style: AppText.screenTitle()),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 3.h),
                child: Text(AppConstants.headerDate,
                    style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── KPI grid (mock) ──
  Widget _kpiGrid(BuildContext context, WidgetRef ref) {
    void goLeads(String tab) {
      ref.read(leadTabProvider.notifier).state = tab;
      context.go(Routes.leads);
    }

    final cards = [
      KpiCard(
        icon: PhosphorIconsFill.userPlus, iconColor: AppColors.success, iconBg: AppColors.tintGreen,
        value: '142', label: 'My New leads', sub: 'This period, all sources',
        accent: AppColors.success, trend: '18.3%', trendUp: true,
        spark: const [96, 104, 100, 112, 120, 131, 142], onTap: () => goLeads('new'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.target, iconColor: AppColors.error, iconBg: AppColors.tintRed,
        value: '26', unit: '%', label: 'My Win rate', sub: 'Won / qualified ratio',
        accent: AppColors.error, trend: '2.3%', trendUp: false,
        spark: const [31, 30, 29, 29, 28, 27, 26], onTap: () => goLeads('won'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.hourglassMedium, iconColor: AppColors.blueBright, iconBg: AppColors.tintBlue,
        value: '42', unit: 'days', label: 'My Quote to cash', sub: 'Quote-to-payment window',
        accent: AppColors.blueBright, trend: '3 days', trendUp: true, arrowUp: false,
        spark: const [51, 49, 48, 46, 45, 44, 42], onTap: () => context.go(Routes.payments),
      ),
      KpiCard(
        icon: PhosphorIconsFill.trendUp, iconColor: AppColors.success, iconBg: AppColors.tintGreen,
        value: '₹2.8', unit: 'Cr', label: 'My Sales Pipeline', sub: 'Pipeline value, all stages',
        accent: AppColors.success, trend: '12.3%', trendUp: true,
        spark: const [1.9, 2.1, 2.2, 2.4, 2.5, 2.6, 2.8], onTap: () => goLeads('all'),
      ),
    ];

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: cards[0]), SizedBox(width: 12.w), Expanded(child: cards[1])],
          ),
        ),
        SizedBox(height: 12.h),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: cards[2]), SizedBox(width: 12.w), Expanded(child: cards[3])],
          ),
        ),
      ],
    );
  }

  // ── KPI grid (API): fixed card chrome + values from the endpoint ──
  Widget _apiKpiGrid(BuildContext context, WidgetRef ref, List<CrmKpiValue> kpis) {
    void goLeads(String tab) {
      ref.read(leadTabProvider.notifier).state = tab;
      context.go(Routes.leads);
    }

    CrmKpiValue at(int i) => i < kpis.length ? kpis[i] : CrmKpiValue.empty;
    String? unitOf(CrmKpiValue v) => v.unit.isEmpty ? null : v.unit;

    final k0 = at(0), k1 = at(1), k2 = at(2), k3 = at(3);
    final cards = [
      KpiCard(
        icon: PhosphorIconsFill.userPlus, iconColor: AppColors.success, iconBg: AppColors.tintGreen,
        value: k0.value, unit: unitOf(k0), label: 'My New leads', sub: 'This period, all sources',
        accent: AppColors.success, trend: k0.trend, trendUp: k0.trendUp, arrowUp: k0.arrowUp,
        progress: k0.progress, onTap: () => goLeads('new'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.target, iconColor: AppColors.success, iconBg: AppColors.tintGreen,
        value: k1.value, unit: unitOf(k1), label: 'My Win rate', sub: 'Won / qualified ratio',
        accent: AppColors.success, trend: k1.trend, trendUp: k1.trendUp, arrowUp: k1.arrowUp,
        progress: k1.progress, onTap: () => goLeads('won'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.hourglassMedium, iconColor: AppColors.blueBright, iconBg: AppColors.tintBlue,
        value: k2.value, unit: unitOf(k2), label: 'My Quote to cash', sub: 'Quote-to-payment window',
        accent: AppColors.blueBright, trend: k2.trend, trendUp: k2.trendUp, arrowUp: k2.arrowUp,
        progress: k2.progress, onTap: () => context.go(Routes.payments),
      ),
      KpiCard(
        icon: PhosphorIconsFill.fileText, iconColor: AppColors.blueBright, iconBg: AppColors.tintBlue,
        value: k3.value, unit: unitOf(k3), label: 'My Quote acceptance', sub: 'Conversion rate',
        accent: AppColors.blueBright, trend: k3.trend, trendUp: k3.trendUp, arrowUp: k3.arrowUp,
        progress: k3.progress, onTap: () => context.go(Routes.quotes),
      ),
    ];

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: cards[0]), SizedBox(width: 12.w), Expanded(child: cards[1])],
          ),
        ),
        SizedBox(height: 12.h),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: cards[2]), SizedBox(width: 12.w), Expanded(child: cards[3])],
          ),
        ),
      ],
    );
  }

  // ── Card shell ──
  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.borderCardSoft),
        boxShadow: [
          BoxShadow(color: const Color(0xFF101828).withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: const Color(0xFF101828).withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }

  Widget _emptyBlock(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 24.h),
      child: Center(
        child: Text(text,
            style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
      ),
    );
  }

  // ── Lead funnel (mock) ──
  Widget _funnelCard(BuildContext context, WidgetRef ref) {
    const data = <(String, String, int)>[
      ('new', 'New', 142),
      ('qualified', 'Qualified', 86),
      ('quote', 'Quote', 54),
      ('negotiation', 'Negotiation', 31),
      ('won', 'Won', 22),
      ('lost', 'Lost', 18),
    ];
    const maxV = 142;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Lead Funnel', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('Lead stages · Manoj Varma', style: AppText.caption(color: AppColors.textPlaceholder)),
          SizedBox(height: 16.h),
          SizedBox(
            height: 132.h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < data.length; i++) ...[
                  if (i > 0) SizedBox(width: 8.w),
                  Expanded(
                    child: _funnelBar(
                      count: data[i].$3,
                      label: data[i].$2,
                      color: StatusMeta$.lead[data[i].$1]!.color,
                      frac: (data[i].$3 / maxV).clamp(0.07, 1.0),
                      dim: data[i].$1 == 'lost',
                      onTap: () {
                        ref.read(leadTabProvider.notifier).state = data[i].$1;
                        context.go(Routes.leads);
                      },
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

  // ── Lead funnel (API): org stages, real counts & colours ──
  Widget _apiFunnelCard(BuildContext context, WidgetRef ref, List<CrmFunnelBar> bars) {
    final maxV = bars.fold<int>(1, (m, b) => b.count > m ? b.count : m);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Lead Funnel', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('Lead stages across your pipeline', style: AppText.caption(color: AppColors.textPlaceholder)),
          SizedBox(height: 16.h),
          if (bars.isEmpty)
            _emptyBlock('No lead data yet.')
          else
            SizedBox(
              height: 132.h,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < bars.length; i++) ...[
                    if (i > 0) SizedBox(width: 8.w),
                    Expanded(
                      child: _funnelBar(
                        count: bars[i].count,
                        label: bars[i].label,
                        color: bars[i].color,
                        frac: (bars[i].count / maxV).clamp(0.07, 1.0),
                        dim: bars[i].tabKey == 'lost',
                        onTap: () {
                          ref.read(leadTabProvider.notifier).state = bars[i].tabKey;
                          context.go(Routes.leads);
                        },
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

  Widget _funnelBar({
    required int count,
    required String label,
    required Color color,
    required double frac,
    required bool dim,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('$count', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
          SizedBox(height: 6.h),
          Expanded(
            child: FractionallySizedBox(
              heightFactor: frac,
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: BoxConstraints(maxWidth: 30.w),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: dim ? color.withOpacity(0.5) : color,
                  borderRadius: BorderRadius.circular(6.r),
                ),
              ),
            ),
          ),
          SizedBox(height: 6.h),
          Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: AppText.custom(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.15)),
        ],
      ),
    );
  }

  // ── First response trend (mock) ──
  Widget _responseTrendCard() {
    const data = <double>[34, 31, 33, 28, 27, 29, 25, 24, 26, 23, 22, 22];
    return _card(
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
                    Text('My First Response Trend', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text('Median response time', style: AppText.caption(color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('22', style: AppText.custom(size: 24, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
                      SizedBox(width: 3.w),
                      Text('min', style: AppText.captionStrong(color: AppColors.textPlaceholder)),
                    ],
                  ),
                  Text('Current median', style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Sparkline(values: data, color: AppColors.blueBright, height: 104.h, strokeWidth: 2.2),
          SizedBox(height: 6.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final m in ['Jan', 'May', 'Sep', 'Dec'])
                Text(m, style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
          ),
        ],
      ),
    );
  }

  // ── First response trend (API): real median headline, no fabricated series ──
  //
  // The dashboard-crm endpoints expose the current first-response median but no
  // time-series, so the card shows the median only — never a made-up sparkline.
  Widget _apiResponseTrendCard(int? median) {
    return _card(
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
                    Text('My First Response', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text('Median response time', style: AppText.caption(color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(median != null ? '$median' : '—',
                          style: AppText.custom(size: 24, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
                      SizedBox(width: 3.w),
                      Text('min', style: AppText.captionStrong(color: AppColors.textPlaceholder)),
                    ],
                  ),
                  Text('Current median', style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text('Response-time trend not available yet.',
              style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ],
      ),
    );
  }

  // ── Section heading ──
  Widget _sectionHeading(IconData icon, Color color, String title) {
    return Padding(
      padding: EdgeInsets.only(left: 2.w),
      child: Row(
        children: [
          Icon(icon, size: 16.sp, color: color),
          SizedBox(width: 7.w),
          Text(title, style: AppText.sectionTitle()),
        ],
      ),
    );
  }

  // ── Attention grid (mock) ──
  Widget _attentionGrid(BuildContext context, WidgetRef ref) {
    final items = <_Attn>[
      _Attn('3', 'Payments missed', delta: '+1', up: false, note: 'Worsening', noteColor: AppColors.error, onTap: () => context.go(Routes.payments)),
      _Attn('4', 'Followups missed', delta: '0', neutral: true, note: 'Steady', noteColor: AppColors.textMuted2, onTap: () {
        ref.read(followupTabProvider.notifier).state = 'overdue';
        context.go(Routes.followups);
      }),
      _Attn('14', 'Tasks missed', delta: '-3', up: true, note: 'Improving', noteColor: AppColors.success, onTap: () {
        ref.read(crmTaskTabProvider.notifier).state = 'overdue';
        context.go(Routes.tasks);
      }),
      _Attn('4', 'Lost after quote', delta: '+1', up: false, note: 'Worsening', noteColor: AppColors.error, onTap: () {
        ref.read(leadTabProvider.notifier).state = 'lost';
        context.go(Routes.leads);
      }),
    ];
    return _attentionLayout(items);
  }

  // ── Attention grid (API): real counts + directions ──
  Widget _apiAttentionGrid(BuildContext context, WidgetRef ref, List<CrmAttentionValue> attn) {
    CrmAttentionValue at(int i) => i < attn.length ? attn[i] : CrmAttentionValue.empty;
    _Attn card(int i, String label, VoidCallback onTap) {
      final v = at(i);
      return _Attn(v.value, label,
          delta: v.delta.isEmpty ? '0' : v.delta, up: v.up, neutral: v.neutral, note: v.note, noteColor: v.noteColor, onTap: onTap);
    }

    final items = <_Attn>[
      card(0, 'Payments missed', () => context.go(Routes.payments)),
      card(1, 'Followups missed', () {
        ref.read(followupTabProvider.notifier).state = 'overdue';
        context.go(Routes.followups);
      }),
      card(2, 'Tasks missed', () {
        ref.read(crmTaskTabProvider.notifier).state = 'overdue';
        context.go(Routes.tasks);
      }),
      card(3, 'Lost after quote', () {
        ref.read(leadTabProvider.notifier).state = 'lost';
        context.go(Routes.leads);
      }),
    ];
    return _attentionLayout(items);
  }

  Widget _attentionLayout(List<_Attn> items) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: _attnCard(items[0])), SizedBox(width: 12.w), Expanded(child: _attnCard(items[1]))],
          ),
        ),
        SizedBox(height: 12.h),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: _attnCard(items[2])), SizedBox(width: 12.w), Expanded(child: _attnCard(items[3]))],
          ),
        ),
      ],
    );
  }

  Widget _attnCard(_Attn a) {
    final Color pillBg = a.neutral ? AppColors.bgChipGrey : (a.up ? AppColors.tintGreen : AppColors.tintRed);
    final Color pillFg = a.neutral ? AppColors.textMuted2 : (a.up ? AppColors.success : AppColors.error);
    final IconData pillIcon = a.neutral
        ? PhosphorIconsBold.arrowRight
        : (a.up ? PhosphorIconsBold.arrowDown : PhosphorIconsBold.arrowUp);

    return GestureDetector(
      onTap: a.onTap,
      child: _card(
        padding: EdgeInsets.all(14.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.value, style: AppText.custom(size: 24, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
            SizedBox(height: 2.h),
            Text(a.label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                  decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(7.r)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(pillIcon, size: 10.sp, color: pillFg),
                      SizedBox(width: 3.w),
                      Text(a.delta, style: AppText.custom(size: 11, weight: FontWeight.w700, color: pillFg)),
                    ],
                  ),
                ),
                Flexible(
                  child: Text(a.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 11, weight: FontWeight.w600, color: a.noteColor)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Recent wins (shared: mock passes const literals, API passes real rows) ──
  Widget _winsCard(
    BuildContext context, {
    required List<WinRow> wins,
    required String countLabel,
    required String totalLabel,
  }) {
    return _card(
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My recent wins', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          Container(
            padding: EdgeInsets.only(top: 8.h, bottom: 10.h),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(countLabel, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.success)),
                const Spacer(),
                Text(totalLabel, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
          if (wins.isEmpty)
            _emptyBlock('No recent wins.')
          else
            for (final w in wins)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push('${w.route}?id=${w.id}'),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                            SizedBox(height: 2.h),
                            Text(w.deal, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption(color: AppColors.textPlaceholder)),
                          ],
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(w.amt, style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.success)),
                          SizedBox(height: 3.h),
                          Text(w.when, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  // ── Overdue items (shared: mock passes const map, API passes real map) ──
  Widget _overdueCard(BuildContext context, WidgetRef ref, {required Map<String, List<OverdueRow>> data}) {
    final tab = ref.watch(crmOverdueTabProvider);
    const chips = <(String, String)>[
      ('fu', 'Follow ups'),
      ('pay', 'Payments'),
      ('quotes', 'Quotes'),
      ('noproj', 'Project not created'),
    ];
    final rows = data[tab] ?? const [];

    return _card(
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overdue items', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 12.h),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (int i = 0; i < chips.length; i++) ...[
                  if (i > 0) SizedBox(width: 8.w),
                  GestureDetector(
                    onTap: () => ref.read(crmOverdueTabProvider.notifier).state = chips[i].$1,
                    child: Container(
                      height: 34.h,
                      padding: EdgeInsets.symmetric(horizontal: 13.w),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tab == chips[i].$1 ? AppColors.navy : AppColors.bgChipGrey,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(chips[i].$2,
                          style: AppText.custom(
                            size: 12.5,
                            weight: tab == chips[i].$1 ? FontWeight.w700 : FontWeight.w600,
                            color: tab == chips[i].$1 ? AppColors.white : AppColors.textLabelAlt,
                          )),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 2.h),
          if (rows.isEmpty)
            _emptyBlock('Nothing overdue here.')
          else
            for (final r in rows)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push('${r.route}?id=${r.id}'),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                            SizedBox(height: 2.h),
                            Text(r.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption(color: AppColors.textPlaceholder)),
                          ],
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(r.amt, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          SizedBox(height: 3.h),
                          Text(r.age, style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.error)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Attn {
  final String value;
  final String label;
  final String delta;
  final bool up;
  final bool neutral;
  final String note;
  final Color noteColor;
  final VoidCallback onTap;
  _Attn(this.value, this.label, {required this.delta, this.up = false, this.neutral = false, required this.note, required this.noteColor, required this.onTap});
}
