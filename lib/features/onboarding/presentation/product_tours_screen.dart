import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/detail_app_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../shell/application/providers/shell_providers.dart';
import '../application/tour_controller.dart';
import '../domain/tour.dart';

/// Every tour for this app with where the user is in it, and Start / Resume /
/// Replay — plus the Auto-start switch and Reset (webapp ToursPanel).
class ProductToursScreen extends ConsumerWidget {
  const ProductToursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(tourControllerProvider);
    final c = ref.read(tourControllerProvider.notifier);

    final groups = <String, List<Tour>>{};
    for (final t in st.catalog) {
      (groups[t.category.isEmpty ? 'Tours' : t.category] ??= []).add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DetailAppBar(section: 'Product tours'),
        Expanded(
          child: RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 32.h),
              children: [
                Text(
                    'Short guided walkthroughs of the app. Start one any time, '
                    'or pick up where you left off.',
                    style: AppText.caption()),
                SizedBox(height: 14.h),
                if (!st.loaded)
                  Padding(
                    padding: EdgeInsets.only(top: 40.h),
                    child: const Center(child: CircularProgressIndicator()),
                  )
                else if (st.catalog.isEmpty)
                  const EmptyState(
                    icon: PhosphorIconsRegular.compass,
                    title: 'No tours yet',
                    body: 'Tours for the mobile app will appear here once '
                        'they are published.',
                  )
                else
                  for (final g in groups.entries) ...[
                    Padding(
                      padding: EdgeInsets.only(top: 6.h, bottom: 8.h),
                      child: Text(g.key.toUpperCase(),
                          style: AppText.custom(
                              size: 11,
                              weight: FontWeight.w700,
                              color: AppColors.textMuted,
                              letterSpacing: 0.6)),
                    ),
                    for (final t in g.value) _tourCard(context, ref, st, t),
                  ],
                SizedBox(height: 18.h),
                _settings(context, ref, st),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tourCard(BuildContext context, WidgetRef ref, TourState st, Tour t) {
    final p = st.progress[t.key];
    final status = p?.status ?? TourStatus.notStarted;
    final steps = t.mobileSteps.length;
    final done = p == null
        ? 0
        : t.mobileSteps.where((s) => p.completedSteps.contains(s.key)).length;
    final blocked = prerequisiteMissing(t, st.progress);
    final preTitle =
        st.catalog.where((x) => x.key == t.prerequisite).firstOrNull?.title ??
            t.prerequisite;

    final (chip, chipFg, chipBg) = p?.outdated == true
        ? ('Updated', AppColors.blueBright, const Color(0xFFE8EEFC))
        : switch (status) {
            TourStatus.notStarted => (
                'Not started',
                AppColors.textMuted,
                const Color(0xFFF1F2F4)
              ),
            TourStatus.inProgress => (
                'In progress ($done of $steps)',
                const Color(0xFFB54708),
                const Color(0xFFFEF4E2)
              ),
            TourStatus.completed => (
                'Completed',
                const Color(0xFF1B6E3A),
                const Color(0xFFE3F4E8)
              ),
            TourStatus.skipped || TourStatus.dismissed => (
                'Skipped',
                AppColors.textMuted,
                const Color(0xFFF1F2F4)
              ),
          };
    final action = switch (status) {
      TourStatus.notStarted => 'Start',
      TourStatus.inProgress => 'Resume',
      _ => 'Replay',
    };

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, style: AppText.bodyStrong()),
                if (t.description.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(t.description, style: AppText.caption()),
                ],
                SizedBox(height: 8.h),
                Wrap(spacing: 6.w, runSpacing: 4.h, children: [
                  _chip(chip, chipFg, chipBg),
                  _chip('$steps steps', AppColors.textMuted,
                      const Color(0xFFF1F2F4)),
                ]),
                if (blocked) ...[
                  SizedBox(height: 6.h),
                  Text('Finish “$preTitle” first',
                      style: AppText.caption(color: AppColors.textPlaceholder)),
                ],
              ],
            ),
          ),
          SizedBox(width: 10.w),
          GestureDetector(
            onTap: blocked
                ? null
                : () {
                    ref.read(drawerOpenProvider.notifier).state = false;
                    if (ref
                        .read(tourControllerProvider.notifier)
                        .start(t.key)) {
                      // The tour opens its own first screen.
                      if (context.canPop()) context.pop();
                    }
                  },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: blocked ? const Color(0xFFE5E7EB) : AppColors.navy,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Text(action,
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w700,
                      color: blocked ? AppColors.textMuted : AppColors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color fg, Color bg) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6.r)),
        child: Text(label,
            style:
                AppText.custom(size: 11, weight: FontWeight.w600, color: fg)),
      );

  Widget _settings(BuildContext context, WidgetRef ref, TourState st) {
    final c = ref.read(tourControllerProvider.notifier);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Offer tours automatically',
                        style: AppText.bodyStrong()),
                    Text('Applies to the web app too.',
                        style: AppText.caption()),
                  ],
                ),
              ),
              Switch.adaptive(
                value: st.autoStartEnabled,
                activeColor: AppColors.navy,
                onChanged: (v) async {
                  try {
                    await c.setAutoStart(v);
                  } on Object {
                    ref
                        .read(toastProvider.notifier)
                        .showError('Couldn’t save that — try again.');
                  }
                },
              ),
            ],
          ),
          const Divider(height: 1, color: AppColors.borderCardSoft),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _confirmReset(context, ref),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 14.h),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.arrowCounterClockwise,
                      size: 18.sp, color: AppColors.textSecondary),
                  SizedBox(width: 10.w),
                  Expanded(
                      child: Text('Reset all tours', style: AppText.body())),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        title: Text('Reset all tours?', style: AppText.cardTitle()),
        content: Text(
            'Your progress in every mobile tour is cleared, and the welcome '
            'tour will be offered again.',
            style: AppText.body()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(tourControllerProvider.notifier).resetAll();
      ref.read(toastProvider.notifier).show('Tours reset');
    } on Object {
      ref.read(toastProvider.notifier).showError('Couldn’t reset — try again.');
    }
  }
}
