import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../application/providers/course_admin_providers.dart';
import '../../infrastructure/data_sources/remote/course_admin_remote_ds.dart';
import '../components/lms_filter_chip.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';
import '../components/lms_learner_card.dart';
import '../components/lms_search_field.dart';
import '../lms_assign.dart';
import '../lms_nav.dart';

/// Webapp `LearnersListScreen`: every user with an enrolment, straight from
/// `GET /lms/learners/` (server status, counts, progress and deadline), with
/// name / role search, role + status filters, Clear filters, refresh, the
/// "All Members" list with View · Nudge, the "Showing n of m : k Overdue"
/// footer with 10 / 25 / 50 rows, and Assign course.
class LmsLearnersScreen extends ConsumerStatefulWidget {
  const LmsLearnersScreen({super.key});

  @override
  ConsumerState<LmsLearnersScreen> createState() => _LmsLearnersScreenState();
}

class _LmsLearnersScreenState extends ConsumerState<LmsLearnersScreen> {
  final _searchCtrl = TextEditingController();
  String _role = 'all';
  String _status = 'all';
  // The app's standard page sizes, 20 / 50 / 100 (UI/UX audit #50).
  int _pageSize = 20;

  static const _statusChips = <(String, String)>[
    ('all', 'All Status'),
    ('completed', 'Completed'),
    ('inprogress', 'In progress'),
    ('overdue', 'Overdue'),
    ('notstarted', 'Not started'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActive =>
      _searchCtrl.text.trim().isNotEmpty || _role != 'all' || _status != 'all';

  void _clear() => setState(() {
        _searchCtrl.clear();
        _role = 'all';
        _status = 'all';
      });

  void _open(LearnerSummary l) =>
      context.push('${Routes.lmsLearnerDetail}?id=${l.userId}');

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(learnerSummariesProvider);
    final learners = async.valueOrNull ?? const <LearnerSummary>[];
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = [
      for (final l in learners)
        if ((q.isEmpty ||
                l.name.toLowerCase().contains(q) ||
                l.roleName.toLowerCase().contains(q)) &&
            (_role == 'all' || l.roleName == _role) &&
            (_status == 'all' || l.status == _status))
          l,
    ];
    final shown = filtered.take(_pageSize).toList();
    final overdueN = filtered.where((l) => l.overdue).length;
    final roleNames = <String>{
      for (final l in learners)
        if (l.roleName.isNotEmpty) l.roleName
    }.toList()
      ..sort();
    final roleChips = <(String, String)>[
      ('all', 'All Roles'),
      for (final r in roleNames) (r, r)
    ];

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context),
            titleGap: 4,
            bottomPadding: 12,
            title: Text('Learners',
                style: AppText.custom(
                    size: 22,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4)),
            trailing: GestureDetector(
              onTap: () => ref.invalidate(learnerSummariesProvider),
              child: Container(
                width: 40.r,
                height: 40.r,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: const Color(0xFFE6E7EA)),
                ),
                child: Icon(PhosphorIconsRegular.arrowClockwise,
                    size: 18.sp, color: AppColors.textSecondary),
              ),
            ),
            bottom: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 2.w, bottom: 12.h),
                  child: Text(
                      'Track training progress and identify overdue members.',
                      style: AppText.custom(
                          size: 12.5,
                          weight: FontWeight.w500,
                          color: AppColors.textMuted)),
                ),
                LmsSearchField(
                  controller: _searchCtrl,
                  hint: 'Search by name or role..',
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: 12.h),
                _chipRow([
                  for (final c in roleChips)
                    LmsFilterChip.solid(
                        label: c.$2,
                        active: _role == c.$1,
                        onTap: () => setState(() => _role = c.$1)),
                ]),
                SizedBox(height: 10.h),
                _chipRow([
                  for (final c in _statusChips)
                    LmsFilterChip.subtle(
                        label: c.$2,
                        active: _status == c.$1,
                        onTap: () => setState(() => _status = c.$1)),
                ]),
              ],
            ),
          ),
          Expanded(
            child: async.isLoading && !async.hasValue
                ? const ListSkeleton()
                : async.hasError && !async.hasValue
                    ? async.error is AppError
                        ? ErrorState.forError(async.error! as AppError,
                            onRetry: () =>
                                ref.invalidate(learnerSummariesProvider))
                        : ErrorState(
                            body: 'Could not load learners.',
                            onRetry: () =>
                                ref.invalidate(learnerSummariesProvider))
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.refresh(learnerSummariesProvider.future),
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 24.h),
                          children: [
                            Padding(
                              padding: EdgeInsets.only(left: 2.w, bottom: 10.h),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text('All Members',
                                        style: AppText.custom(
                                            size: 16,
                                            weight: FontWeight.w700,
                                            color: AppColors.textPrimary)),
                                  ),
                                  if (_hasActive)
                                    GestureDetector(
                                      onTap: _clear,
                                      child: Text('Clear filters',
                                          style: AppText.custom(
                                              size: 13,
                                              weight: FontWeight.w700,
                                              color: AppColors.textMuted)),
                                    ),
                                ],
                              ),
                            ),
                            if (shown.isEmpty)
                              _empty(noData: learners.isEmpty)
                            else
                              for (final l in shown) ...[
                                LmsLearnerCard(
                                  name: l.name,
                                  rid: l.rid,
                                  role: l.roleName,
                                  statusKey: l.status,
                                  pct: l.pct,
                                  assigned: l.assigned,
                                  completed: l.completed,
                                  deadlineLabel: l.deadline == null
                                      ? '—'
                                      : absoluteDate(l.deadline),
                                  overdue: l.overdue,
                                  onTap: () => _open(l),
                                  onNudge: () => nudgeAllCourses(context, ref,
                                      userId: l.userId, name: l.name),
                                ),
                                SizedBox(height: 11.h),
                              ],
                            SizedBox(height: 4.h),
                            _pager(shown.length, learners.length, overdueN),
                          ],
                        ),
                      ),
          ),
          LmsFooter(
            child: LmsCtaButton(
                label: 'Assign course',
                icon: PhosphorIconsBold.plus,
                onTap: () => assignFromLearners(context, ref)),
          ),
        ],
      ),
    );
  }

  Widget _chipRow(List<Widget> chips) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (int i = 0; i < chips.length; i++) ...[
              if (i > 0) SizedBox(width: 8.w),
              chips[i],
            ],
          ],
        ),
      );

  Widget _pager(int shown, int total, int overdueN) {
    final style = AppText.custom(
        size: 13, weight: FontWeight.w500, color: AppColors.textSecondary);
    return Row(
      children: [
        Expanded(
          child: Text.rich(TextSpan(
            text: 'Showing $shown of $total learners',
            style: style,
            children: [
              if (overdueN > 0)
                TextSpan(
                  text: ': $overdueN Overdue',
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.error),
                ),
            ],
          )),
        ),
        PopupMenuButton<int>(
          onSelected: (n) => setState(() => _pageSize = n),
          itemBuilder: (_) => [
            for (final n in const [20, 50, 100])
              PopupMenuItem(value: n, child: Text('$n'))
          ],
          child: Container(
            height: 34.h,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: const Color(0xFFE6E7EA)),
            ),
            child: Row(
              children: [
                Text('$_pageSize', style: style),
                SizedBox(width: 6.w),
                Icon(PhosphorIconsBold.caretDown,
                    size: 12.sp, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty({required bool noData}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 42.h),
      child: Column(
        children: [
          Container(
            width: 66.r,
            height: 66.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.borderCardSoft,
                borderRadius: BorderRadius.circular(19.r)),
            child: Icon(PhosphorIconsRegular.student,
                size: 30.sp, color: AppColors.textPlaceholder),
          ),
          SizedBox(height: 16.h),
          Text(noData ? 'No learners yet' : 'No learners match your filters',
              style: AppText.sectionTitle(), textAlign: TextAlign.center),
          if (_hasActive) ...[
            SizedBox(height: 10.h),
            GestureDetector(
              onTap: _clear,
              child: Text('Clear filters',
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.blueBright)),
            ),
          ],
        ],
      ),
    );
  }
}
