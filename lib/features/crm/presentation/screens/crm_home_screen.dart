import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/config/constants.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/inr_format.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/sparkline.dart';
import '../../../dashboard/application/dash_navigation.dart';
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
void _quickAdd(BuildContext context, WidgetRef ref) {
  final actions = [
    if (hasPermission(ref, 'lead', PermVerb.create))
      ('Add lead', PhosphorIconsRegular.userPlus, Routes.addLead),
    if (hasPermission(ref, 'task', PermVerb.create))
      ('Add task', PhosphorIconsRegular.checkSquare, Routes.addCrmTask),
    // Webapp quick action `/customers?new=1`: the list with Add customer open.
    if (hasPermission(ref, 'customer', PermVerb.create))
      (
        'Add customer',
        PhosphorIconsRegular.buildings,
        '${Routes.customers}?new=1'
      ),
  ];
  if (actions.isEmpty) {
    ref.read(toastProvider.notifier).showError(permissionCopy(PermVerb.create));
    return;
  }
  // The customers list is a top-level tab, so it is navigated to, not pushed.
  void open(BuildContext c, String route) =>
      route.startsWith(Routes.customers) ? c.go(route) : c.push(route);
  if (actions.length == 1) {
    open(context, actions.first.$3);
    return;
  }
  showClozrSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(title: 'Quick add', onClose: () => Navigator.of(ctx).pop()),
        for (final a in actions)
          ListTile(
            leading: Icon(a.$2, color: AppColors.navy),
            title: Text(a.$1, style: AppText.bodyStrong()),
            onTap: () {
              Navigator.of(ctx).pop();
              open(context, a.$3);
            },
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

class CrmHomeScreen extends ConsumerWidget {
  const CrmHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Webapp dashboard quick actions: the `+` here offers each create the role
    // allows ("Add lead", "Add task").
    registerAdd(
        ref, AddAction(label: 'Quick add', run: (ctx) => _quickAdd(ctx, ref)));
    return Column(
      children: [
        _header(context, ref),
        Expanded(
          child: ApiConfig.apiEnabled
              ? _apiBody(context, ref)
              : _mockList(context, ref),
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
          _sectionHeading(PhosphorIconsFill.warningCircle, AppColors.warning,
              'Attention needed'),
          SizedBox(height: 11.h),
          _attentionGrid(context, ref),
          SizedBox(height: 16.h),
          _winsCard(context,
              wins: crmRecentWins,
              countLabel: crmWinsCount,
              totalLabel: crmWinsTotal),
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
                type: AppErrorType.unknown,
                message: 'Something went wrong. Please try again.');
        // Every widget here is a `dashboard-crm/*` call, and those are gated
        // on the `dashboard` module even at `scope=own` — a plain CRM User is
        // refused with "…view the admin dashboard", which reads as a broken
        // screen when all they opened was Home. Say what it is, and that
        // Retry will not change it.
        final forbidden = err.type == AppErrorType.forbidden;
        return ListView(
          children: [
            if (forbidden)
              const ErrorState(
                icon: PhosphorIconsFill.lock,
                iconColor: AppColors.textMuted,
                iconBg: AppColors.bgLight,
                title: 'Overview not included in your role',
                body: 'The CRM overview needs the Dashboard permission. '
                    'Your leads, follow-ups and tasks are in the bar below.',
              )
            else
              ErrorState.forError(err,
                  onRetry: () => ref.invalidate(crmHomeProvider)),
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
            _sectionHeading(PhosphorIconsFill.warningCircle, AppColors.warning,
                'Attention needed'),
            SizedBox(height: 11.h),
            _apiAttentionGrid(context, ref, d.attention),
            SizedBox(height: 16.h),
            _winsCard(
              context,
              wins: d.wins,
              countLabel:
                  '${d.winsCount} ${d.winsCount == 1 ? 'deal' : 'deals'} won',
              totalLabel: '${formatInr(d.winsTotal)} total value',
            ),
            SizedBox(height: 16.h),
            _overdueCard(context, ref, data: d.overdue),
          ],
        ),
      ),
    );
  }

  /// `mine=1` for a Leads link — the cards are the signed-in user's own
  /// figures (`scope=own` = owner OR assignee, the list's `is_teams`).
  static String _mineQuery(WidgetRef ref) => 'mine=1';

  /// `from=…&to=…` for the Home's selected period.
  static String _periodQuery(WidgetRef ref) => crmPeriodQuery(
      ref.read(crmPeriodProvider), ref.read(crmCustomRangeProvider));

  // ── Header ──
  /// The webapp's dashboard Period selector: a chip showing the active period
  /// that opens the list (This month … Custom range). Everything on the page
  /// that is period-based refetches for the pick.
  Widget _periodPicker(BuildContext context, WidgetRef ref) {
    final period = ref.watch(crmPeriodProvider);
    final range = ref.watch(crmCustomRangeProvider);
    String d(DateTime t) => '${t.day} '
        '${const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ][t.month - 1]} ${t.year}';
    final label = period == CrmPeriod.custom && range != null
        ? '${d(range.start)} – ${d(range.end)}'
        : period.label;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _pickPeriod(context, ref),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: const Color(0xFFE6E7EA)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.calendarBlank,
                  size: 14.sp, color: AppColors.textSecondary),
              SizedBox(width: 6.w),
              Text('Period · $label', style: AppText.bodyStrong()),
              SizedBox(width: 6.w),
              Icon(PhosphorIconsBold.caretDown,
                  size: 11.sp, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPeriod(BuildContext context, WidgetRef ref) async {
    final current = ref.read(crmPeriodProvider);
    final picked = await showClozrSheet<CrmPeriod>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Period'),
          for (final p in CrmPeriod.values)
            ListTile(
              title: Text(p.label,
                  style: p == current
                      ? AppText.bodyStrong()
                      : AppText.body(color: AppColors.textPrimary)),
              trailing: p == current
                  ? Icon(PhosphorIconsBold.check,
                      size: 16.sp, color: AppColors.blueBright)
                  : null,
              onTap: () => Navigator.of(ctx).pop(p),
            ),
          SizedBox(height: 12.h),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    if (picked == CrmPeriod.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: ref.read(crmCustomRangeProvider),
      );
      if (range == null) return;
      ref.read(crmCustomRangeProvider.notifier).state = range;
    }
    ref.read(crmPeriodProvider.notifier).state = picked;
  }

  Widget _header(BuildContext context, WidgetRef ref) {
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
                    Text('CRM',
                        style: AppText.custom(
                            size: 13,
                            weight: FontWeight.w500,
                            color: AppColors.textMuted)),
                    SizedBox(height: 1.h),
                    Text('Dashboard', style: AppText.screenTitle()),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 3.h),
                child: Text(AppConstants.headerDate,
                    style: AppText.custom(
                        size: 12,
                        weight: FontWeight.w600,
                        color: AppColors.textPlaceholder)),
              ),
            ],
          ),
          if (ApiConfig.apiEnabled) ...[
            SizedBox(height: 10.h),
            _periodPicker(context, ref),
          ],
        ],
      ),
    );
  }

  // ── KPI grid (mock) ──
  Widget _kpiGrid(BuildContext context, WidgetRef ref) {
    // Through dashGo so the Leads list opens on exactly this stage with any
    // earlier drawer filter (a source / member picked from the Dashboard)
    // cleared first.
    // The cards count the signed-in user's leads in the selected period
    // (`scope=own` + period), so the list opens on the same set: assigned to
    // me, and — for the created-in-period figures — created in that window.
    // "My New leads" is leads *created* this period, whatever their stage
    // (the funnel can read New 0 beside New leads 7); "My Win rate" is my Won
    // group (a status TYPE, so "Won" and "Won – repeat order" both count).
    final mine = _mineQuery(ref);
    void goLeads(String tab) => dashGo(
        context,
        ref,
        switch (tab) {
          'new' => '${Routes.leads}?$mine&${_periodQuery(ref)}',
          'won' => '${Routes.leads}?group=won&$mine&${_periodQuery(ref)}',
          _ => '${Routes.leads}?$mine',
        });

    final cards = [
      KpiCard(
        icon: PhosphorIconsFill.userPlus,
        iconColor: AppColors.success,
        iconBg: AppColors.tintGreen,
        value: '142',
        label: 'My New leads',
        sub: 'This period, all sources',
        accent: AppColors.success,
        trend: '18.3%',
        trendUp: true,
        spark: const [96, 104, 100, 112, 120, 131, 142],
        onTap: () => goLeads('new'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.target,
        iconColor: AppColors.error,
        iconBg: AppColors.tintRed,
        value: '26',
        unit: '%',
        label: 'My Win rate',
        sub: 'Won / qualified ratio',
        accent: AppColors.error,
        trend: '2.3%',
        trendUp: false,
        spark: const [31, 30, 29, 29, 28, 27, 26],
        onTap: () => goLeads('won'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.hourglassMedium,
        iconColor: AppColors.blueBright,
        iconBg: AppColors.tintBlue,
        value: '42',
        unit: 'days',
        label: 'My Quote to cash',
        sub: 'Quote-to-payment window',
        accent: AppColors.blueBright,
        trend: '3 days',
        trendUp: true,
        arrowUp: false,
        spark: const [51, 49, 48, 46, 45, 44, 42],
        // Quote-to-payment window: the payment plans.
        onTap: () => dashGo(context, ref, '${Routes.payments}?mode=payments'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.trendUp,
        iconColor: AppColors.success,
        iconBg: AppColors.tintGreen,
        value: '₹2.8',
        unit: 'Cr',
        label: 'My Sales Pipeline',
        sub: 'Pipeline value, all stages',
        accent: AppColors.success,
        trend: '12.3%',
        trendUp: true,
        spark: const [1.9, 2.1, 2.2, 2.4, 2.5, 2.6, 2.8],
        onTap: () => goLeads('all'),
      ),
    ];

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              SizedBox(width: 12.w),
              Expanded(child: cards[1])
            ],
          ),
        ),
        SizedBox(height: 12.h),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[2]),
              SizedBox(width: 12.w),
              Expanded(child: cards[3])
            ],
          ),
        ),
      ],
    );
  }

  // ── KPI grid (API): fixed card chrome + values from the endpoint ──
  Widget _apiKpiGrid(
      BuildContext context, WidgetRef ref, List<CrmKpiValue> kpis) {
    // Through dashGo so the Leads list opens on exactly this stage with any
    // earlier drawer filter (a source / member picked from the Dashboard)
    // cleared first.
    // The cards count the signed-in user's leads in the selected period
    // (`scope=own` + period), so the list opens on the same set: assigned to
    // me, and — for the created-in-period figures — created in that window.
    // "My New leads" is leads *created* this period, whatever their stage
    // (the funnel can read New 0 beside New leads 7); "My Win rate" is my Won
    // group (a status TYPE, so "Won" and "Won – repeat order" both count).
    final mine = _mineQuery(ref);
    void goLeads(String tab) => dashGo(
        context,
        ref,
        switch (tab) {
          'new' => '${Routes.leads}?$mine&${_periodQuery(ref)}',
          'won' => '${Routes.leads}?group=won&$mine&${_periodQuery(ref)}',
          _ => '${Routes.leads}?$mine',
        });

    CrmKpiValue at(int i) => i < kpis.length ? kpis[i] : CrmKpiValue.empty;
    String? unitOf(CrmKpiValue v) => v.unit.isEmpty ? null : v.unit;

    final k0 = at(0), k1 = at(1), k2 = at(2), k3 = at(3);
    final cards = [
      KpiCard(
        icon: PhosphorIconsFill.userPlus,
        iconColor: AppColors.success,
        iconBg: AppColors.tintGreen,
        value: k0.value,
        unit: unitOf(k0),
        label: 'My New leads',
        sub: 'This period, all sources',
        accent: AppColors.success,
        trend: k0.trend,
        trendUp: k0.trendUp,
        arrowUp: k0.arrowUp,
        progress: k0.progress,
        onTap: () => goLeads('new'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.target,
        iconColor: AppColors.success,
        iconBg: AppColors.tintGreen,
        value: k1.value,
        unit: unitOf(k1),
        label: 'My Win rate',
        sub: 'Won / qualified ratio',
        accent: AppColors.success,
        trend: k1.trend,
        trendUp: k1.trendUp,
        arrowUp: k1.arrowUp,
        progress: k1.progress,
        onTap: () => goLeads('won'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.hourglassMedium,
        iconColor: AppColors.blueBright,
        iconBg: AppColors.tintBlue,
        value: k2.value,
        unit: unitOf(k2),
        label: 'My Quote to cash',
        sub: 'Quote-to-payment window',
        accent: AppColors.blueBright,
        trend: k2.trend,
        trendUp: k2.trendUp,
        arrowUp: k2.arrowUp,
        progress: k2.progress,
        // Quote-to-payment window: the payment plans.
        onTap: () => dashGo(context, ref, '${Routes.payments}?mode=payments'),
      ),
      KpiCard(
        icon: PhosphorIconsFill.fileText,
        iconColor: AppColors.blueBright,
        iconBg: AppColors.tintBlue,
        value: k3.value,
        unit: unitOf(k3),
        label: 'My Quote acceptance',
        sub: 'Conversion rate',
        accent: AppColors.blueBright,
        trend: k3.trend,
        trendUp: k3.trendUp,
        arrowUp: k3.arrowUp,
        progress: k3.progress,
        // The acceptance rate's numerator: accepted quotes.
        onTap: () =>
            // Accepted among the quotes created in the period.
            dashGo(context, ref,
                '${Routes.quotes}?status=accepted&${_periodQuery(ref)}'),
      ),
    ];

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              SizedBox(width: 12.w),
              Expanded(child: cards[1])
            ],
          ),
        ),
        SizedBox(height: 12.h),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[2]),
              SizedBox(width: 12.w),
              Expanded(child: cards[3])
            ],
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
          BoxShadow(
              color: const Color(0xFF101828).withOpacity(0.04),
              blurRadius: 2,
              offset: const Offset(0, 1)),
          BoxShadow(
              color: const Color(0xFF101828).withOpacity(0.05),
              blurRadius: 24,
              offset: const Offset(0, 10)),
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
            style: AppText.custom(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.textPlaceholder)),
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
          Text('My Lead Funnel',
              style: AppText.custom(
                  size: 15,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('Lead stages · Manoj Varma',
              style: AppText.caption(color: AppColors.textPlaceholder)),
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
                      onTap: () => dashGo(context, ref,
                          '${Routes.leads}?stage=${data[i].$1}&${_mineQuery(ref)}'),
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
  Widget _apiFunnelCard(
      BuildContext context, WidgetRef ref, List<CrmFunnelBar> bars) {
    final maxV = bars.fold<int>(1, (m, b) => b.count > m ? b.count : m);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Lead Funnel',
              style: AppText.custom(
                  size: 15,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('Lead stages across your pipeline',
              style: AppText.caption(color: AppColors.textPlaceholder)),
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
                        // The org's own stage: the Leads chips are keyed by
                        // the status name (`CatalogOption.key`), not the
                        // legacy five-stage key behind the bar colour.
                        // My leads of this stage, created in the period —
                        // the set the bar counted.
                        onTap: () => dashGo(
                            context,
                            ref,
                            '${Routes.leads}?stage='
                            '${Uri.encodeQueryComponent(bars[i].label.trim().toLowerCase())}'
                            '&${_mineQuery(ref)}&${_periodQuery(ref)}'),
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
          Text('$count',
              style: AppText.custom(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AppColors.textSecondary)),
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
              style: AppText.custom(
                  size: 10,
                  weight: FontWeight.w500,
                  color: AppColors.textMuted,
                  height: 1.15)),
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
                    Text('My First Response Trend',
                        style: AppText.custom(
                            size: 15,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text('Median response time',
                        style:
                            AppText.caption(color: AppColors.textPlaceholder)),
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
                      Text('22',
                          style: AppText.custom(
                              size: 24,
                              weight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5)),
                      SizedBox(width: 3.w),
                      Text('min',
                          style: AppText.captionStrong(
                              color: AppColors.textPlaceholder)),
                    ],
                  ),
                  Text('Current median',
                      style: AppText.custom(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: AppColors.textPlaceholder)),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Sparkline(
              values: data,
              color: AppColors.blueBright,
              height: 104.h,
              strokeWidth: 2.2),
          SizedBox(height: 6.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final m in ['Jan', 'May', 'Sep', 'Dec'])
                Text(m,
                    style: AppText.custom(
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: AppColors.textPlaceholder)),
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
                    Text('My First Response',
                        style: AppText.custom(
                            size: 15,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text('Median response time',
                        style:
                            AppText.caption(color: AppColors.textPlaceholder)),
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
                          style: AppText.custom(
                              size: 24,
                              weight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5)),
                      SizedBox(width: 3.w),
                      Text('min',
                          style: AppText.captionStrong(
                              color: AppColors.textPlaceholder)),
                    ],
                  ),
                  Text('Current median',
                      style: AppText.custom(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: AppColors.textPlaceholder)),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text('Response-time trend not available yet.',
              style: AppText.custom(
                  size: 12,
                  weight: FontWeight.w500,
                  color: AppColors.textPlaceholder)),
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
      _Attn('3', 'Payments missed',
          delta: '+1',
          up: false,
          note: 'Worsening',
          noteColor: AppColors.error,
          // Overdue payments due in the period (the card's own scope — the
          // lead's owner / assignee — has no Payments facet; noted in UAT).
          onTap: () => dashGo(context, ref,
              '${Routes.payments}?mode=payments&tab=overdue&${_periodQuery(ref)}')),
      _Attn('4', 'Followups missed',
          delta: '0',
          neutral: true,
          note: 'Steady',
          noteColor: AppColors.textMuted2,
          onTap: () =>
              // My overdue follow-ups due in the period.
              dashGo(context, ref,
                  '${Routes.followups}?tab=overdue&mine=1&${_periodQuery(ref)}')),
      _Attn('14', 'Tasks missed',
          delta: '-3',
          up: true,
          note: 'Improving',
          noteColor: AppColors.success,
          onTap: () => dashGo(context, ref,
              '${Routes.tasks}?tab=overdue&mine=1&${_periodQuery(ref)}')),
      _Attn('4', 'Lost after quote',
          delta: '+1',
          up: false,
          note: 'Worsening',
          noteColor: AppColors.error,
          // The Lost group: every stage the org typed `lost`, whatever its name.
          onTap: () => dashGo(
              context, ref, '${Routes.leads}?group=lost&${_mineQuery(ref)}')),
    ];
    return _attentionLayout(items);
  }

  // ── Attention grid (API): real counts + directions ──
  Widget _apiAttentionGrid(
      BuildContext context, WidgetRef ref, List<CrmAttentionValue> attn) {
    CrmAttentionValue at(int i) =>
        i < attn.length ? attn[i] : CrmAttentionValue.empty;
    _Attn card(int i, String label, VoidCallback onTap) {
      final v = at(i);
      return _Attn(v.value, label,
          delta: v.delta.isEmpty ? '0' : v.delta,
          up: v.up,
          neutral: v.neutral,
          note: v.note,
          noteColor: v.noteColor,
          onTap: onTap);
    }

    final items = <_Attn>[
      // Each card counts a slice; its tap opens exactly that slice (and clears
      // whatever the list had picked before) — see dashGo.
      card(
          0,
          'Payments missed',
          () => dashGo(context, ref,
              '${Routes.payments}?mode=payments&tab=overdue&${_periodQuery(ref)}')),
      card(
          1,
          'Followups missed',
          () => dashGo(context, ref,
              '${Routes.followups}?tab=overdue&mine=1&${_periodQuery(ref)}')),
      card(
          2,
          'Tasks missed',
          () => dashGo(context, ref,
              '${Routes.tasks}?tab=overdue&mine=1&${_periodQuery(ref)}')),
      // The Lost group: every stage the org typed `lost`, whatever its name.
      card(
          3,
          'Lost after quote',
          () => dashGo(context, ref,
              '${Routes.leads}?group=lost&${_mineQuery(ref)}&${_periodQuery(ref)}')),
    ];
    return _attentionLayout(items);
  }

  Widget _attentionLayout(List<_Attn> items) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _attnCard(items[0])),
              SizedBox(width: 12.w),
              Expanded(child: _attnCard(items[1]))
            ],
          ),
        ),
        SizedBox(height: 12.h),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _attnCard(items[2])),
              SizedBox(width: 12.w),
              Expanded(child: _attnCard(items[3]))
            ],
          ),
        ),
      ],
    );
  }

  Widget _attnCard(_Attn a) {
    final Color pillBg = a.neutral
        ? AppColors.bgChipGrey
        : (a.up ? AppColors.tintGreen : AppColors.tintRed);
    final Color pillFg = a.neutral
        ? AppColors.textMuted2
        : (a.up ? AppColors.success : AppColors.error);
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
            Text(a.value,
                style: AppText.custom(
                    size: 24,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5)),
            SizedBox(height: 2.h),
            Text(a.label,
                style: AppText.custom(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: AppColors.textLabelAlt)),
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                  decoration: BoxDecoration(
                      color: pillBg, borderRadius: BorderRadius.circular(7.r)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(pillIcon, size: 10.sp, color: pillFg),
                      SizedBox(width: 3.w),
                      Text(a.delta,
                          style: AppText.custom(
                              size: 11,
                              weight: FontWeight.w700,
                              color: pillFg)),
                    ],
                  ),
                ),
                Flexible(
                  child: Text(a.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(
                          size: 11,
                          weight: FontWeight.w600,
                          color: a.noteColor)),
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
          Text('My recent wins',
              style: AppText.custom(
                  size: 15,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          Container(
            padding: EdgeInsets.only(top: 8.h, bottom: 10.h),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.bgLight))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(countLabel,
                    style: AppText.custom(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppColors.success)),
                const Spacer(),
                Text(totalLabel,
                    style: AppText.custom(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppColors.textPrimary)),
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
                  decoration: const BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: AppColors.bgLight))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            SizedBox(height: 2.h),
                            Text(w.deal,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption(
                                    color: AppColors.textPlaceholder)),
                          ],
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(w.amt,
                              style: AppText.custom(
                                  size: 13.5,
                                  weight: FontWeight.w800,
                                  color: AppColors.success)),
                          SizedBox(height: 3.h),
                          Text(w.when,
                              style: AppText.custom(
                                  size: 11,
                                  weight: FontWeight.w500,
                                  color: AppColors.textPlaceholder)),
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
  Widget _overdueCard(BuildContext context, WidgetRef ref,
      {required Map<String, List<OverdueRow>> data}) {
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
          Text('Overdue items',
              style: AppText.custom(
                  size: 15,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          SizedBox(height: 12.h),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (int i = 0; i < chips.length; i++) ...[
                  if (i > 0) SizedBox(width: 8.w),
                  GestureDetector(
                    onTap: () => ref
                        .read(crmOverdueTabProvider.notifier)
                        .state = chips[i].$1,
                    child: Container(
                      height: 34.h,
                      padding: EdgeInsets.symmetric(horizontal: 13.w),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tab == chips[i].$1
                            ? AppColors.navy
                            : AppColors.bgChipGrey,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(chips[i].$2,
                          style: AppText.custom(
                            size: 12.5,
                            weight: tab == chips[i].$1
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: tab == chips[i].$1
                                ? AppColors.white
                                : AppColors.textLabelAlt,
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
                  decoration: const BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: AppColors.bgLight))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            SizedBox(height: 2.h),
                            Text(r.sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption(
                                    color: AppColors.textPlaceholder)),
                          ],
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(r.amt,
                              style: AppText.custom(
                                  size: 13.5,
                                  weight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: 3.h),
                          Text(r.age,
                              style: AppText.custom(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: AppColors.error)),
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
  _Attn(this.value, this.label,
      {required this.delta,
      this.up = false,
      this.neutral = false,
      required this.note,
      required this.noteColor,
      required this.onTap});
}
