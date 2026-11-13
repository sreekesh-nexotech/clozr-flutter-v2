import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../application/providers/course_admin_providers.dart';
import '../../infrastructure/data_sources/remote/course_admin_remote_ds.dart';

/// What an assignment did, for the caller's toast.
class AssignOutcome {
  const AssignOutcome(this.courseTitle, this.enrolled, {this.courseId = ''});
  final String courseTitle;
  final String courseId;
  final int enrolled;
}

/// Webapp `AssignCourseModal`: Course* (pre-selected), Learners* with a
/// name / role search and ticks, an optional Deadline, Cancel / Assign
/// course. Posts `/lms/learners/assign/`; a refusal is toasted by the shell
/// with the server's words and the sheet stays open. Null when cancelled.
///
/// [learners] replaces the org list (the learner detail offers only that
/// learner); [preselect] is ticked on open.
Future<AssignOutcome?> showAssignCourseSheet(
  BuildContext context, {
  required List<(String, String)> courses,
  List<AssignableUser>? learners,
  String? preselect,
}) {
  return showClozrSheet<AssignOutcome>(
    context: context,
    builder: (_) => _AssignCourseSheet(
        courses: courses, learners: learners, preselect: preselect),
  );
}

class _AssignCourseSheet extends ConsumerStatefulWidget {
  const _AssignCourseSheet(
      {required this.courses, this.learners, this.preselect});

  /// `(course id, label)` — the published courses on offer.
  final List<(String, String)> courses;
  final List<AssignableUser>? learners;
  final String? preselect;

  @override
  ConsumerState<_AssignCourseSheet> createState() => _AssignCourseSheetState();
}

class _AssignCourseSheetState extends ConsumerState<_AssignCourseSheet> {
  late String _courseId = widget.courses.isEmpty ? '' : widget.courses.first.$1;
  late final Set<String> _selected = {if (widget.preselect case final id?) id};
  final _search = TextEditingController();
  DateTime? _deadline;
  String? _errCourse;
  String? _errLearners;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errCourse = _courseId.isEmpty ? 'Pick a course' : null;
      _errLearners = _selected.isEmpty ? 'Pick at least one learner' : null;
    });
    if (_errCourse != null || _errLearners != null) return;
    setState(() => _busy = true);
    try {
      final n = await ref.read(courseAdminRemoteProvider).assign(
          courseId: _courseId,
          userIds: _selected.toList(),
          deadline: _deadline);
      if (!mounted) return;
      final title = widget.courses.firstWhere((c) => c.$1 == _courseId).$2;
      Navigator.of(context).pop(AssignOutcome(title, n, courseId: _courseId));
    } on Object {
      // The shell's failure toast carries the server message; stay open.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDeadline() async {
    // Otherwise focus returns to the learner search when the picker closes
    // and the keyboard covers the list again.
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) setState(() => _deadline = d);
  }

  Widget _label(String t, {bool req = false}) => Padding(
        padding: EdgeInsets.only(bottom: 7.h),
        child: Text.rich(TextSpan(
          text: t,
          style: AppText.custom(
              size: 13,
              weight: FontWeight.w700,
              color: AppColors.textSecondary),
          children: [
            if (req)
              TextSpan(
                  text: ' *',
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.error))
          ],
        )),
      );

  Widget _err(String? e) => e == null
      ? const SizedBox.shrink()
      : Padding(
          padding: EdgeInsets.only(top: 6.h),
          child: Text(e,
              style: AppText.custom(
                  size: 12, weight: FontWeight.w600, color: AppColors.error)),
        );

  BoxDecoration _box({bool error = false}) => BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(11.r),
        border:
            Border.all(color: error ? AppColors.error : AppColors.borderInput),
      );

  @override
  Widget build(BuildContext context) {
    final users = widget.learners != null
        ? AsyncData(widget.learners!)
        : ref.watch(assignableUsersProvider);
    final q = _search.text.trim().toLowerCase();
    final list = [
      for (final u in users.valueOrNull ?? const <AssignableUser>[])
        if (q.isEmpty ||
            u.name.toLowerCase().contains(q) ||
            u.role.toLowerCase().contains(q))
          u,
    ];
    final courseTitle = widget.courses
        .where((c) => c.$1 == _courseId)
        .map((c) => c.$2)
        .firstOrNull;

    // ClozrSheetContainer already lifts the sheet above the keyboard; adding
    // the inset here too squeezed the learner list to nothing while searching.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
            title: 'Assign course', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 12.h),
            children: [
              _label('Course', req: true),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() => _courseId = v),
                itemBuilder: (_) => [
                  for (final c in widget.courses)
                    PopupMenuItem(value: c.$1, child: Text(c.$2))
                ],
                child: Container(
                  height: 46.h,
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  decoration: _box(error: _errCourse != null),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(courseTitle ?? 'No published courses',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.custom(
                                size: 14,
                                weight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ),
                      Icon(PhosphorIconsBold.caretDown,
                          size: 13.sp, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              _err(_errCourse),
              SizedBox(height: 16.h),
              _label('Learners', req: true),
              Container(
                height: 44.h,
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                decoration: _box(),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.magnifyingGlass,
                        size: 16.sp, color: AppColors.textPlaceholder),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        style: AppText.custom(
                            size: 14,
                            weight: FontWeight.w500,
                            color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search by name or role..',
                          hintStyle: AppText.custom(
                              size: 14,
                              weight: FontWeight.w500,
                              color: AppColors.textPlaceholder),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10.h),
              Container(
                constraints: BoxConstraints(maxHeight: 260.h),
                decoration: _box(error: _errLearners != null),
                child: users.isLoading && !users.hasValue
                    ? Padding(
                        padding: EdgeInsets.all(16.r),
                        child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : list.isEmpty
                        ? Padding(
                            padding: EdgeInsets.all(16.r),
                            child: Text('No learners match your search',
                                textAlign: TextAlign.center,
                                style: AppText.custom(
                                    size: 13,
                                    weight: FontWeight.w500,
                                    color: AppColors.textPlaceholder)),
                          )
                        : ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.symmetric(vertical: 4.h),
                            children: [
                              for (final u in list)
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() {
                                    _selected.contains(u.id)
                                        ? _selected.remove(u.id)
                                        : _selected.add(u.id);
                                    // A tick answers "Pick at least one learner".
                                    if (_selected.isNotEmpty)
                                      _errLearners = null;
                                  }),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 12.w, vertical: 9.h),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _selected.contains(u.id)
                                              ? PhosphorIconsFill.checkSquare
                                              : PhosphorIconsRegular.square,
                                          size: 20.sp,
                                          color: _selected.contains(u.id)
                                              ? AppColors.navy
                                              : AppColors.textPlaceholder,
                                        ),
                                        SizedBox(width: 10.w),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(u.name,
                                                  style: AppText.custom(
                                                      size: 14,
                                                      weight: FontWeight.w600,
                                                      color: AppColors
                                                          .textPrimary)),
                                              if (u.role.isNotEmpty)
                                                Text(u.role,
                                                    style: AppText.custom(
                                                        size: 12,
                                                        weight: FontWeight.w500,
                                                        color: AppColors
                                                            .textPlaceholder)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
              ),
              _err(_errLearners),
              SizedBox(height: 16.h),
              _label('Deadline'),
              GestureDetector(
                onTap: _pickDeadline,
                child: Container(
                  height: 46.h,
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  decoration: _box(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                            _deadline == null
                                ? 'No deadline'
                                : absoluteDate(_deadline),
                            style: AppText.custom(
                                size: 14,
                                weight: FontWeight.w500,
                                color: _deadline == null
                                    ? AppColors.textPlaceholder
                                    : AppColors.textPrimary)),
                      ),
                      if (_deadline != null)
                        GestureDetector(
                          onTap: () => setState(() => _deadline = null),
                          child: Padding(
                            padding: EdgeInsets.only(right: 8.w),
                            child: Icon(PhosphorIconsBold.x,
                                size: 14.sp, color: AppColors.textMuted),
                          ),
                        ),
                      Icon(PhosphorIconsRegular.calendarBlank,
                          size: 17.sp, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 18.h),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 48.h,
                    alignment: Alignment.center,
                    decoration: _box(),
                    child: Text('Cancel',
                        style: AppText.custom(
                            size: 14.5,
                            weight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _busy ? null : _submit,
                  child: Container(
                    height: 48.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _busy ? AppColors.textPlaceholder : AppColors.navy,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(_busy ? 'Assigning…' : 'Assign course',
                        style: AppText.custom(
                            size: 14.5,
                            weight: FontWeight.w700,
                            color: AppColors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
