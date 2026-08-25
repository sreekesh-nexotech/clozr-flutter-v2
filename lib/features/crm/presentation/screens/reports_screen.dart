import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/inr_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/lead.dart';

/// Reports — sales performance charts computed live from the leads dataset:
/// summary KPIs, a lead funnel, leads-by-status and top lead sources.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  static const _funnel = ['new', 'qualified', 'quote', 'negotiation', 'won'];

  /// Statuses that count toward open pipeline value (everything that isn't a
  /// closed outcome).
  static const _closed = {'won', 'lost', 'archived'};

  /// Pull-to-refresh. Every figure on this screen is derived from the lead list,
  /// so refetching it is the whole refresh.
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(leadsScopedProvider);
    await settle([ref.read(leadsProvider.future)]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leadsProvider);
    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: AsyncStateView<List<Lead>>(
              value: async,
              onRetry: () => ref.invalidate(leadsProvider),
              onRefresh: () => _refresh(ref),
              data: _body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(List<Lead> leads) {
    final total = leads.length;
    final won = leads.where((l) => l.status == 'won').length;
    final winRate = total == 0 ? 0 : (won / total * 100).round();

    int countOf(String k) => leads.where((l) => l.status == k).length;
    final funnelCounts = {for (final k in _funnel) k: countOf(k)};
    final fmax = [1, ...funnelCounts.values].reduce((a, b) => a > b ? a : b);

    // Open pipeline = summed value of leads still in play (not won/lost/archived).
    final openPipelineNum = leads
        .where((l) => !_closed.contains(l.status))
        .fold<int>(0, (sum, l) => sum + l.valueNum);
    final openPipeline = openPipelineNum == 0 ? '—' : formatInr(openPipelineNum);

    final srcCounts = <String, int>{};
    for (final l in leads) {
      srcCounts[l.source] = (srcCounts[l.source] ?? 0) + 1;
    }
    final sources = srcCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final srcMax = [1, ...srcCounts.values].reduce((a, b) => a > b ? a : b);
    final statusMax = [1, ...StatusMeta$.leadOrder.map(countOf)].reduce((a, b) => a > b ? a : b);

    return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 120.h),
      children: [
        _summaryGrid(total, won, winRate, openPipeline),
        SizedBox(height: 16.h),
        _funnelCard(funnelCounts, fmax),
        SizedBox(height: 16.h),
        _statusCard(countOf, statusMax),
        SizedBox(height: 16.h),
        _sourcesCard(sources, srcMax),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 12.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.canPop() ? context.pop() : context.go(Routes.dashboard),
            child: Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: const Color(0xFFE6E7EA)),
              ),
              child: Icon(PhosphorIconsBold.caretLeft, size: 17.sp, color: AppColors.textBody),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reports', style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                Text('Sales performance', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(9.r)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsRegular.calendarBlank, size: 14.sp, color: AppColors.textLabelAlt),
                SizedBox(width: 6.w),
                Text('This month', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid(int total, int won, int winRate, String openPipeline) {
    final cards = <_KpiDef>[
      _KpiDef('Total leads', '$total', PhosphorIconsFill.usersThree, AppColors.blueBright, AppColors.tintBlue),
      _KpiDef('Won deals', '$won', PhosphorIconsFill.trophy, AppColors.success, AppColors.tintGreen),
      _KpiDef('Win rate', '$winRate%', PhosphorIconsFill.target, AppColors.warning, AppColors.tintAmber),
      _KpiDef('Open pipeline', openPipeline, PhosphorIconsFill.wallet, AppColors.navy, AppColors.tintNavy),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: [_kpiCard(cards[0]), SizedBox(height: 12.h), _kpiCard(cards[2])])),
        SizedBox(width: 12.w),
        Expanded(child: Column(children: [_kpiCard(cards[1]), SizedBox(height: 12.h), _kpiCard(cards[3])])),
      ],
    );
  }

  Widget _kpiCard(_KpiDef k) {
    return ClozrCard(
      radius: 15,
      padding: EdgeInsets.all(14.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30.w,
            height: 30.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: k.bg, borderRadius: BorderRadius.circular(9.r)),
            child: Icon(k.icon, size: 16.sp, color: k.color),
          ),
          SizedBox(height: 11.h),
          Text(k.value, style: AppText.custom(size: 24, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
          SizedBox(height: 1.h),
          Text(k.label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
        ],
      ),
    );
  }

  Widget _funnelCard(Map<String, int> counts, int fmax) {
    return ClozrCard(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lead funnel', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('Pipeline stages · all leads', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          SizedBox(height: 16.h),
          SizedBox(
            height: 150.h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final k in _funnel)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${counts[k]}', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
                        SizedBox(height: 6.h),
                        FractionallySizedBox(
                          widthFactor: 0.78,
                          child: Container(
                            height: (18 + (counts[k]! / fmax) * 88).h,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [_chartTeal, _chartNavy],
                              ),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(8.r), bottom: Radius.circular(3.r)),
                            ),
                          ),
                        ),
                        SizedBox(height: 6.h),
                        Text(_funnelLabel(k),
                            textAlign: TextAlign.center,
                            style: AppText.custom(size: 10.5, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.15)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(int Function(String) countOf, int smax) {
    return ClozrCard(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Leads by status', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 15.h),
          for (int i = 0; i < StatusMeta$.leadOrder.length; i++) ...[
            if (i > 0) SizedBox(height: 13.h),
            _statusBar(StatusMeta$.leadOrder[i], countOf(StatusMeta$.leadOrder[i]), smax),
          ],
        ],
      ),
    );
  }

  Widget _statusBar(String key, int count, int smax) {
    final meta = StatusMeta$.lead[key]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
            SizedBox(width: 7.w),
            Expanded(child: Text(meta.label, style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary))),
            Text('$count', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        SizedBox(height: 6.h),
        _bar(count / smax, meta.color),
      ],
    );
  }

  Widget _sourcesCard(List<MapEntry<String, int>> sources, int srcMax) {
    return ClozrCard(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top lead sources', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 15.h),
          for (int i = 0; i < sources.length; i++) ...[
            if (i > 0) SizedBox(height: 13.h),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(sources[i].key, style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary))),
                    Text('${sources[i].value}', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
                SizedBox(height: 6.h),
                _bar(sources[i].value / srcMax, AppColors.blueBright),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bar(double factor, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9999.r),
      child: Container(
        height: 8.h,
        color: AppColors.borderCardSoft,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: factor.clamp(0.0, 1.0),
          child: Container(color: color),
        ),
      ),
    );
  }

  String _funnelLabel(String key) => key == 'quote' ? 'Quote' : StatusMeta$.lead[key]!.label;
}

class _KpiDef {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bg;
  const _KpiDef(this.label, this.value, this.icon, this.color, this.bg);
}

/// The prototype's funnel gradient stops — no design tokens exist for them.
const Color _chartTeal = Color(0xFF3AA0B8);
const Color _chartNavy = Color(0xFF0B1C3F);
