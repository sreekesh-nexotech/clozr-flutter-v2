import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../../shell/domain/nav_catalog.dart';
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
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Coming back to the Dashboard after time elsewhere: refresh a bundle that
    // has gone stale (the notifier skips a fresh one and one still loading).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ApiConfig.apiEnabled) return;
      ref.read(dashboardDataNotifierProvider.notifier).maybeRefresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Nothing here may fetch until the role is known. After sign-in the router
    // parks here while `/auth/me/modules/` is still in flight, and watching
    // the data notifier below starts ~20 admin-dashboard calls at once — for a
    // role without the `dashboard` module every one is a 403, each a "no
    // permission" toast, a moment before the redirect moves the user on to
    // their real landing screen. Hold on a plain skeleton instead; a role
    // that lacks the module is redirected from here without a single call.
    if (ApiConfig.apiEnabled) {
      final accessAsync = ref.watch(moduleAccessProvider);
      final access = accessAsync.valueOrNull;
      final unresolved = accessAsync.isLoading && !accessAsync.hasValue;
      if (unresolved ||
          (access != null && !access.canAny(dashboardModuleKeys))) {
        return ColoredBox(
          color: AppColors.bgScreen,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18.w, 120.h, 18.w, 0),
            child: const _DashboardSkeleton(),
          ),
        );
      }
    }
    // A `?tab=` the role cannot see (a stale deep link, or a module removed
    // since) falls back to the first panel it can, matching the bottom nav.
    final tabs =
        visibleDashboardTabs(ref.watch(moduleAccessProvider).valueOrNull);
    final requested =
        GoRouterState.of(context).uri.queryParameters['tab'] ?? 'business';
    final tab =
        tabs.contains(requested) ? requested : (tabs.firstOrNull ?? 'business');
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

    // A reload over data that is already on screen (period / team / member
    // change, refresh, return to the screen): dim the old figures and show a
    // thin progress bar so they are not read as the new selection's numbers.
    final refreshing = phase.loading && phase.settled && phase.error == null;

    final Widget body;
    if (phase.error != null) {
      body = ErrorState.forError(
        phase.error!,
        onRetry: () =>
            ref.read(dashboardDataNotifierProvider.notifier).reload(),
      );
    } else if (!phase.settled && phase.loading) {
      body = const _DashboardSkeleton();
    } else {
      // A distinct key per tab so panel state (segments) resets cleanly when
      // switching panels.
      body = KeyedSubtree(
        key: ValueKey(tab),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: refreshing ? 0.4 : 1,
          child: IgnorePointer(ignoring: refreshing, child: panel),
        ),
      );
    }

    // The app locks text scaling to 1.0 at the root. The Dashboard honours the
    // system font size up to 1.3×: numbers and labels become readable for
    // large-text users while the dense KPI grid still fits.
    final systemScaler = MediaQueryData.fromView(View.of(context)).textScaler;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler:
              systemScaler.clamp(minScaleFactor: 1, maxScaleFactor: 1.3)),
      child: ColoredBox(
        color: AppColors.bgScreen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DashboardHeader(),
            SizedBox(
              height: 2.h,
              child: refreshing
                  ? const LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: AppColors.bgScreen,
                      color: AppColors.blueBright)
                  : null,
            ),
            Expanded(
              // One pull covers all four panels: the bundle behind business / crm
              // / ops / help is a single fetch, and `reload` re-runs it against
              // the period and team currently selected.
              child: AppRefresh(
                onRefresh: () => settle([
                  ref.read(dashboardDataNotifierProvider.notifier).reload(),
                ]),
                child: ListView(
                  // A fresh scroll position per tab: Helpdesk must not open
                  // already scrolled to wherever Operations was left.
                  key: PageStorageKey<String>('dashboard-$tab'),
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
