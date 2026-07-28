import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/lms_providers.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/lms_logic.dart';
import '../../infrastructure/data_sources/local/lms_people.dart';
import '../components/lms_filter_chip.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';
import '../components/lms_learner_card.dart';
import '../components/lms_search_field.dart';
import '../lms_nav.dart';

/// A computed learner row for the list.
class _LearnerVM {
  final String rid;
  final String name;
  final String initials;
  final Color color;
  final String role;
  final String agg;
  final int pct;
  final String coursesLabel;
  final String deadlineLabel;
  final bool overdue;
  const _LearnerVM(this.rid, this.name, this.initials, this.color, this.role, this.agg, this.pct,
      this.coursesLabel, this.deadlineLabel, this.overdue);
}

/// Learners — search, role + status filters, progress cards, Nudge, and the
/// assign-course CTA.
class LmsLearnersScreen extends ConsumerStatefulWidget {
  const LmsLearnersScreen({super.key});

  @override
  ConsumerState<LmsLearnersScreen> createState() => _LmsLearnersScreenState();
}

class _LmsLearnersScreenState extends ConsumerState<LmsLearnersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(lmsLearnerSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  _LearnerVM _vm(LearnerRecord r, Course? Function(String) courseOf) {
    final person = LmsPeople.of(r.rid);
    final agg = LmsLogic.aggStatus(r, courseOf);
    final pct = r.courses.isEmpty
        ? 0
        : (r.courses.map(LmsLogic.pct).reduce((a, b) => a + b) / r.courses.length).round();
    // Next non-completed deadline.
    final dls = <Course>[
      for (final e in r.courses)
        if (courseOf(e.courseId) != null &&
            courseOf(e.courseId)!.deadlineISO.isNotEmpty &&
            !LmsLogic.done(e))
          courseOf(e.courseId)!,
    ]..sort((a, b) => a.deadlineISO.compareTo(b.deadlineISO));
    final dlLabel = dls.isNotEmpty ? 'Deadline: ${dls.first.deadline}' : 'No deadline';
    final coursesLabel = '${r.courses.length} ${r.courses.length == 1 ? 'course' : 'courses'}';
    return _LearnerVM(r.rid, person.name, person.initials, person.color, person.role, agg, pct,
        coursesLabel, dlLabel, agg == 'overdue');
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(lmsRecordsProvider);
    final courseOf = ref.watch(lmsCourseLookupProvider);
    final roleF = ref.watch(lmsRoleFilterProvider);
    final statusF = ref.watch(lmsStatusFilterProvider);
    final query = ref.watch(lmsLearnerSearchProvider).trim().toLowerCase();

    var rows = records.where((r) => r.rid != 'me').map((r) => _vm(r, courseOf)).toList();
    if (roleF != 'all') rows = rows.where((x) => x.role == roleF).toList();
    if (statusF != 'all') rows = rows.where((x) => x.agg == statusF).toList();
    if (query.isNotEmpty) {
      rows = rows.where((x) => '${x.name} ${x.role}'.toLowerCase().contains(query)).toList();
    }

    final roleChips = <(String, String)>[
      ('all', 'All roles'),
      ('Manager', 'Manager'),
      ('Sales rep', 'Sales rep'),
      ('Project associate', 'Project associate'),
      ('Viewer', 'Viewer'),
    ];
    final statusChips = <(String, String)>[
      ('all', 'All status'),
      ('notstarted', 'Not started'),
      ('inprogress', 'In progress'),
      ('completed', 'Completed'),
      ('overdue', 'Overdue'),
    ];

    void toast(String m) => ref.read(toastProvider.notifier).show(m);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context),
            titleGap: 4,
            bottomPadding: 12,
            title: Text('Learners',
                style: AppText.custom(size: 22, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
            bottom: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 2.w, bottom: 12.h),
                  child: Text('Track progress and identify overdue members.',
                      style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                ),
                LmsSearchField(
                  controller: _searchCtrl,
                  hint: 'Search members…',
                  onChanged: (v) => ref.read(lmsLearnerSearchProvider.notifier).state = v,
                ),
                SizedBox(height: 12.h),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (int i = 0; i < roleChips.length; i++) ...[
                        if (i > 0) SizedBox(width: 8.w),
                        LmsFilterChip.solid(
                          label: roleChips[i].$2,
                          active: roleF == roleChips[i].$1,
                          onTap: () => ref.read(lmsRoleFilterProvider.notifier).state = roleChips[i].$1,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 10.h),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (int i = 0; i < statusChips.length; i++) ...[
                        if (i > 0) SizedBox(width: 7.w),
                        LmsFilterChip.subtle(
                          label: statusChips[i].$2,
                          active: statusF == statusChips[i].$1,
                          onTap: () => ref.read(lmsStatusFilterProvider.notifier).state = statusChips[i].$1,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? ListView(
                    padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 40.h),
                    children: [_empty()],
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 40.h),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => SizedBox(height: 11.h),
                    itemBuilder: (context, i) {
                      final x = rows[i];
                      return LmsLearnerCard(
                        name: x.name,
                        initials: x.initials,
                        avatarColor: x.color,
                        role: x.role,
                        statusKey: x.agg,
                        pct: x.pct,
                        coursesLabel: x.coursesLabel,
                        deadlineLabel: x.deadlineLabel,
                        overdue: x.overdue,
                        onTap: () => context.push('${Routes.lmsLearnerDetail}?id=${x.rid}'),
                        onNudge: () => toast('Reminder sent to ${x.name.split(' ').first}'),
                      );
                    },
                  ),
          ),
          LmsFooter(
            child: LmsCtaButton(label: 'Assign course', onTap: () => toast('Assign course')),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 42.h),
      child: Column(
        children: [
          Container(
            width: 66.r,
            height: 66.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.borderCardSoft, borderRadius: BorderRadius.circular(19.r)),
            child: Icon(PhosphorIconsRegular.student, size: 30.sp, color: AppColors.textPlaceholder),
          ),
          SizedBox(height: 16.h),
          Text('No learners match your search', style: AppText.sectionTitle(), textAlign: TextAlign.center),
          SizedBox(height: 10.h),
          GestureDetector(
            onTap: () {
              _searchCtrl.clear();
              ref.read(lmsRoleFilterProvider.notifier).state = 'all';
              ref.read(lmsStatusFilterProvider.notifier).state = 'all';
              ref.read(lmsLearnerSearchProvider.notifier).state = '';
            },
            child: Text('Clear filters',
                style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
          ),
        ],
      ),
    );
  }
}
