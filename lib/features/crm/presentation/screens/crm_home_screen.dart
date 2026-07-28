import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/config/constants.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/sparkline.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/crm_home_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';

/// CRM Home dashboard — KPI grid, lead funnel, first-response trend, attention
/// grid, recent wins and an overdue-items module (design lines 48–207).
class CrmHomeScreen extends ConsumerWidget {
  const CrmHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: ListView(
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
              _winsCard(context),
              SizedBox(height: 16.h),
              _overdueCard(context, ref),
            ],
          ),
        ),
      ],
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

  // ── KPI grid ──
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
        accent: AppColors.blueBright, trend: '3 days', trendUp: true,
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

  // ── Lead funnel ──
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

  // ── First response trend ──
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

  // ── Attention grid ──
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

  // ── Recent wins ──
  Widget _winsCard(BuildContext context) {
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
                Text(crmWinsCount, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.success)),
                const Spacer(),
                Text(crmWinsTotal, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
          for (final w in crmRecentWins)
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

  // ── Overdue items ──
  Widget _overdueCard(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(crmOverdueTabProvider);
    const chips = <(String, String)>[
      ('fu', 'Follow ups'),
      ('pay', 'Payments'),
      ('quotes', 'Quotes'),
      ('noproj', 'Project not created'),
    ];
    final rows = crmOverdueData[tab] ?? const [];

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
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(
                child: Text('Nothing overdue here.',
                    style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ),
            )
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
