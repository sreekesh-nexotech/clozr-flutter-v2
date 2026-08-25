import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../application/providers/dashboard_providers.dart';
import '../../domain/entities/dash_colors.dart';
import '../../domain/entities/dashboard_models.dart';
import 'member_picker_sheet.dart';
import 'period_picker_sheet.dart';
import 'team_picker_sheet.dart';

/// The team + period scope chips shown under the panel header. The team chip is
/// hidden on the Business/admin panel. Both chips open their picker sheets and
/// reflect the current selection in their label.
class ScopeChips extends ConsumerWidget {
  const ScopeChips({super.key, required this.scopeModule});

  /// The `module` the Member dropdown is fetched with (`crm` | `pmo`), or null
  /// to show the Period chip alone.
  ///
  /// Null on the Business panel, which has no per-team view, and on Helpdesk:
  /// `dashboard-issue/*` accepts only `scope` — no `team_id`, no `user_id`
  /// (`admin_helpdesk_dashboard.md`, Known gaps) — so both chips are hidden
  /// there rather than shown doing nothing.
  final String? scopeModule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardDataProvider);
    final teamId = ref.watch(dashTeamProvider);
    final memberId = ref.watch(dashMemberProvider);
    final period = ref.watch(dashPeriodProvider);
    final teamSelected = teamId != 'all';
    final module = scopeModule;

    final optionsKey = (module: module ?? '', teamId: teamId);
    final members = module == null
        ? const <DashTeamOption>[]
        : ref.watch(dashMemberOptionsProvider(optionsKey)).valueOrNull ??
            const <DashTeamOption>[];

    // Drop a selection the current list no longer offers. Switching panels
    // changes `module`, and the users feed lists only people who can read that
    // module — so a CRM member carried onto Operations would keep filtering
    // every widget while the chip claimed "All members".
    if (module != null) {
      ref.listen(dashMemberOptionsProvider(optionsKey), (_, next) {
        final list = next.valueOrNull;
        if (list == null) return;
        final selected = ref.read(dashMemberProvider);
        if (selected.isNotEmpty && !list.any((m) => m.id == selected)) {
          ref.read(dashMemberProvider.notifier).state = '';
        }
      });
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        children: [
          if (module != null) ...[
            _TeamChip(
              label: dashTeamLabel(data, teamId),
              active: teamSelected,
              onTap: () => showDashTeamPicker(context, ref, data.teamOptions),
            ),
            _MemberChip(
              label: dashMemberLabel(members, memberId),
              active: memberId.isNotEmpty,
              onTap: () => showDashMemberPicker(context, ref, members),
            ),
          ],
          _PeriodChip(
            label: period,
            onTap: () => showDashPeriodPicker(context, ref, period),
          ),
        ],
      ),
    );
  }
}

/// Same shape as [_TeamChip] with a single-person glyph.
class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: active ? AppColors.navy : AppColors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: active ? null : Border.all(color: DashColors.chipStroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.user, size: 15.sp, color: active ? AppColors.white : AppColors.textSecondary),
            SizedBox(width: 7.w),
            Text(label,
                style: AppText.custom(
                    size: 12.5, weight: FontWeight.w700, color: active ? AppColors.white : AppColors.textSecondary)),
            SizedBox(width: 7.w),
            Icon(PhosphorIconsBold.caretDown,
                size: 11.sp, color: (active ? AppColors.white : AppColors.textSecondary).withOpacity(0.65)),
          ],
        ),
      ),
    );
  }
}

class _TeamChip extends StatelessWidget {
  const _TeamChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: active ? AppColors.navy : AppColors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: active ? null : Border.all(color: DashColors.chipStroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.usersThree, size: 15.sp, color: active ? AppColors.white : AppColors.textSecondary),
            SizedBox(width: 7.w),
            Text(label,
                style: AppText.custom(
                    size: 12.5, weight: FontWeight.w700, color: active ? AppColors.white : AppColors.textSecondary)),
            SizedBox(width: 7.w),
            Icon(PhosphorIconsBold.caretDown, size: 11.sp, color: (active ? AppColors.white : AppColors.textSecondary).withOpacity(0.65)),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: DashColors.chipStroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.calendarBlank, size: 15.sp, color: AppColors.textSecondary),
            SizedBox(width: 7.w),
            Text('Period', style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
            SizedBox(width: 6.w),
            Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
            SizedBox(width: 7.w),
            Icon(PhosphorIconsBold.caretDown, size: 11.sp, color: AppColors.textSecondary.withOpacity(0.65)),
          ],
        ),
      ),
    );
  }
}
