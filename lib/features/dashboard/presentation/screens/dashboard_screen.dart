import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
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
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = GoRouterState.of(context).uri.queryParameters['tab'] ?? 'business';

    final bool showTeam = tab != 'business';
    final Widget panel = switch (tab) {
      'crm' => const CrmPanel(),
      'ops' => const OpsPanel(),
      'help' => const HelpPanel(),
      _ => const BusinessPanel(),
    };

    return ColoredBox(
      color: AppColors.bgScreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardHeader(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
              children: [
                ScopeChips(showTeam: showTeam),
                // A distinct key per tab so panel state (segments) resets cleanly
                // when switching panels.
                KeyedSubtree(key: ValueKey(tab), child: panel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
