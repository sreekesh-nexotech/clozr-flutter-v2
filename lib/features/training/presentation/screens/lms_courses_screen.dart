import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../application/providers/lms_providers.dart';
import '../../domain/entities/course.dart';
import '../components/lms_course_card.dart';
import '../components/lms_filter_chip.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';
import '../components/lms_search_field.dart';
import '../lms_nav.dart';

/// All Courses — persistent search, status chips, course cards and an empty
/// state.
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
    if (c.isPublished) {
      context.push('${Routes.lmsCourseDetail}?id=${c.id}');
    } else {
      context.push('${Routes.lmsBuilder}?id=${c.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(lmsCoursesProvider);
    final records = ref.watch(lmsRecordsProvider);
    final status = ref.watch(lmsCourseStatusProvider);
    final query = ref.watch(lmsCourseSearchProvider).trim().toLowerCase();

    var list = courses.where((c) => status == 'all' || c.status == status);
    if (query.isNotEmpty) {
      list = list.where((c) => '${c.title} ${c.sub}'.toLowerCase().contains(query));
    }
    final rows = list.toList();

    final chips = <(String, String)>[('all', 'All'), ('published', 'Published'), ('draft', 'Drafts')];

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context),
            title: Text('All Courses',
                style: AppText.custom(size: 22, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
            titleGap: 12,
            bottomPadding: 12,
            bottom: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LmsSearchField(
                  controller: _searchCtrl,
                  hint: 'Search courses…',
                  onChanged: (v) => ref.read(lmsCourseSearchProvider.notifier).state = v,
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    for (int i = 0; i < chips.length; i++) ...[
                      if (i > 0) SizedBox(width: 8.w),
                      LmsFilterChip.solid(
                        label: chips[i].$2,
                        active: status == chips[i].$1,
                        onTap: () => ref.read(lmsCourseStatusProvider.notifier).state = chips[i].$1,
                      ),
                    ],
                  ],
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
                    itemBuilder: (context, i) => LmsCourseCard.from(
                      course: rows[i],
                      records: records,
                      onTap: () => _openCourse(rows[i]),
                      onEdit: () => context.push('${Routes.lmsBuilder}?id=${rows[i].id}'),
                    ),
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
            child: Icon(PhosphorIconsRegular.bookOpenText, size: 30.sp, color: AppColors.textPlaceholder),
          ),
          SizedBox(height: 16.h),
          Text('No courses found', style: AppText.sectionTitle()),
          SizedBox(height: 6.h),
          Text('Try a different search or status filter.',
              textAlign: TextAlign.center,
              style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
