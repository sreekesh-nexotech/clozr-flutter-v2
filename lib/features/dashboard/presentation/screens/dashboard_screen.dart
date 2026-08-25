import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../application/providers/dashboard_providers.dart';
import '../components/dashboard_header.dart';
import '../components/panels/business_panel.dart';
import '../components/panels/crm_panel.dart';
import '../components/panels/help_panel.dart';
import '../components/panels/ops_panel.dart';
import '../components/scope_chips.dart';

/// The Dashboard screen. It hosts the four manager/admin panels; the active one
/// is chosen by the `?tab=` query the Dashboard bottom nav sets
/// (business | crm | ops | help — default business). The shell draws the status
/// bar and the Dashboard bottom nav; this screen owns only the panel body.
///
/// In API mode the body branches on the load phase — a first load shows a
/// skeleton, a total failure shows an [ErrorState] with Retry, and success
/// shows the panels (a genuinely empty section renders its own honest zeros).
/// In mock mode the phase is pre-settled, so the panels paint the seed exactly
/// as before. The header + scope chips stay visible in every phase.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = GoRouterState.of(context).uri.queryParameters['tab'] ?? 'business';
    final phase = ref.watch(dashboardDataNotifierProvider);

    // The `module` the Member dropdown needs, which also decides whether the
    // team/member chips render at all. Business has no per-team view, and the
    // Helpdesk widgets take neither param — see [ScopeChips.scopeModule].
    final String? scopeModule = switch (tab) {
      'crm' => 'crm',
      'ops' => 'pmo',
      _ => null,
    };
    final Widget panel = switch (tab) {
      'crm' => const CrmPanel(),
      'ops' => const OpsPanel(),
      'help' => const HelpPanel(),
      _ => const BusinessPanel(),
    };

    final Widget body;
    if (phase.error != null) {
      body = ErrorState.forError(
        phase.error!,
        onRetry: () => ref.read(dashboardDataNotifierProvider.notifier).reload(),
      );
    } else if (!phase.settled && phase.loading) {
      body = const _DashboardSkeleton();
    } else {
      // A distinct key per tab so panel state (segments) resets cleanly when
      // switching panels.
      body = KeyedSubtree(key: ValueKey(tab), child: panel);
    }

    return ColoredBox(
      color: AppColors.bgScreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardHeader(),
          Expanded(
            // One pull covers all four panels: the bundle behind business / crm
            // / ops / help is a single fetch, and `reload` re-runs it against
            // the period and team currently selected.
            child: AppRefresh(
              onRefresh: () => settle([
                ref.read(dashboardDataNotifierProvider.notifier).reload(),
              ]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                children: [
                  ScopeChips(scopeModule: scopeModule),
                  body,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// First-load placeholder for the dashboard body: a shimmering KPI grid over a
/// couple of card blocks, sized to sit inside the outer [ListView].
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget kpi() => Expanded(child: SkeletonBox(height: 116.h, radius: 16));
    return Shimmer.fromColors(
      baseColor: AppColors.borderCardSoft,
      highlightColor: AppColors.bgScreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [kpi(), SizedBox(width: 12.w), kpi()]),
          SizedBox(height: 12.h),
          Row(children: [kpi(), SizedBox(width: 12.w), kpi()]),
          SizedBox(height: 16.h),
          SkeletonBox(height: 180.h, radius: 16),
          SizedBox(height: 16.h),
          SkeletonBox(height: 160.h, radius: 16),
        ],
      ),
    );
  }
}
