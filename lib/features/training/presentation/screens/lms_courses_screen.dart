import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../application/providers/lms_providers.dart';
import '../../domain/entities/course.dart';
import '../components/lms_course_card.dart';
import '../components/lms_filter_chip.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';
import '../components/lms_search_field.dart';
import '../lms_course_actions.dart';
import '../lms_nav.dart';

/// Webapp `AllCoursesScreen` (Training › Course builder): "All Courses" with
/// search on title / role names, status filter, Clear filters, per-course
/// View / Edit / Delete (platform courses View only) and a "Showing N of M"
/// count.
class LmsCoursesScreen extends ConsumerStatefulWidget {
  const LmsCoursesScreen({super.key});

  @override
  ConsumerState<LmsCoursesScreen> createState() => _LmsCoursesScreenState();
}

class _LmsCoursesScreenState extends ConsumerState<LmsCoursesScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(lmsCourseSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openCourse(Course c) {
    // Platform courses are read-only for tenants — always the detail.
    if (c.isPublished || c.isGlobal) {
      context.push('${Routes.lmsCourseDetail}?id=${c.id}');
    } else {
      context.push('${Routes.lmsBuilder}?id=${c.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(lmsCoursesProvider);
    final records = ref.watch(lmsRecordsProvider);
    final load = lmsCombine([
      ref.watch(lmsCoursesControllerProvider),
      ref.watch(lmsRecordsControllerProvider),
    ]);
    final status = ref.watch(lmsCourseStatusProvider);
    final query = ref.watch(lmsCourseSearchProvider).trim().toLowerCase();

    var list = courses.where((c) => status == 'all' || c.status == status);
    if (query.isNotEmpty) {
      list = list.where((c) =>
          c.title.toLowerCase().contains(query) ||
          c.listSubtitle.toLowerCase().contains(query));
    }
    final rows = list.toList();
    final hasActive = query.isNotEmpty || status != 'all';
    void clear() {
      _searchCtrl.clear();
      ref.read(lmsCourseSearchProvider.notifier).state = '';
      ref.read(lmsCourseStatusProvider.notifier).state = 'all';
    }

    final chips = <(String, String)>[
      ('all', 'All Status'),
      ('published', 'Published'),
      ('draft', 'Draft')
    ];

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context),
            title: Text('Course builder',
                style: AppText.custom(
                    size: 22,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4)),
            titleGap: 12,
            bottomPadding: 12,
            bottom: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LmsSearchField(
                  controller: _searchCtrl,
                  hint: 'Search courses..',
                  onChanged: (v) =>
                      ref.read(lmsCourseSearchProvider.notifier).state = v,
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    for (int i = 0; i < chips.length; i++) ...[
                      if (i > 0) SizedBox(width: 8.w),
                      LmsFilterChip.solid(
                        label: chips[i].$2,
                        active: status == chips[i].$1,
                        onTap: () => ref
                            .read(lmsCourseStatusProvider.notifier)
                            .state = chips[i].$1,
                      ),
                    ],
                    const Spacer(),
                    if (hasActive)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: clear,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 4.w, vertical: 6.h),
                          child: Text('Clear filters',
                              style: AppText.custom(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: AppColors.navy)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: load.loading
                ? const ListSkeleton()
                : load.error != null
                    ? ErrorState.forError(load.error!,
                        onRetry: () => reloadLms(ref))
                    : ListView(
                        padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 40.h),
                        children: [
                          Text('All Courses',
                              style: AppText.custom(
                                  size: 19,
                                  weight: FontWeight.w800,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: 3.h),
                          Text(
                              'Create, edit and publish the training your team is assigned.',
                              style: AppText.custom(
                                  size: 13,
                                  weight: FontWeight.w500,
                                  color: AppColors.textMuted)),
                          SizedBox(height: 14.h),
                          if (rows.isEmpty)
                            _empty(
                                noCourses: courses.isEmpty,
                                hasActive: hasActive,
                                onClear: clear),
                          for (int i = 0; i < rows.length; i++) ...[
                            if (i > 0) SizedBox(height: 11.h),
                            LmsCourseCard.from(
                              course: rows[i],
                              records: records,
                              builderList: true,
                              onTap: () => _openCourse(rows[i]),
                              onEdit: () => context.push(
                                  '${Routes.lmsBuilder}?id=${rows[i].id}'),
                              onDelete: () => deleteCourseWithConfirm(
                                  context, ref, rows[i]),
                            ),
                          ],
                          Padding(
                            padding: EdgeInsets.only(top: 14.h),
                            child: Text(
                                'Showing ${rows.length} of ${courses.length} courses',
                                style: AppText.custom(
                                    size: 13,
                                    weight: FontWeight.w500,
                                    color: AppColors.textMuted)),
                          ),
                        ],
                      ),
          ),
          LmsFooter(
            child: LmsCtaButton(
              label: 'New course',
              icon: PhosphorIconsBold.plus,
              onTap: () => context.push(Routes.lmsBuilder),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(
      {required bool noCourses,
      required bool hasActive,
      required VoidCallback onClear}) {
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
            child: Icon(PhosphorIconsRegular.bookOpenText,
                size: 30.sp, color: AppColors.textPlaceholder),
          ),
          SizedBox(height: 16.h),
          Text(noCourses ? 'No courses yet' : 'No courses match your filters',
              style: AppText.sectionTitle()),
          if (hasActive) ...[
            SizedBox(height: 12.h),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: Container(
                height: 38.h,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: AppColors.borderInput),
                ),
                child: Text('Clear filters',
                    style: AppText.custom(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
