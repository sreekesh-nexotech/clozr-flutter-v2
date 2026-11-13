import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_error.dart';
import '../../../data/api/roster.dart';
import '../../../data/api/user_directory.dart';
import '../../crm/domain/entities/crm_catalog.dart';
import '../../crm/presentation/components/option_picker_sheet.dart';
import '../../shell/application/providers/shell_providers.dart';
import '../application/providers/course_admin_providers.dart';
import '../application/providers/lms_providers.dart';
import '../domain/entities/learner_record.dart';
import '../infrastructure/data_sources/remote/course_admin_remote_ds.dart';
import 'components/lms_assign_course_sheet.dart';

/// The "Assign course" flow, shared by the course detail, the Learners list and
/// the learner detail — every one of which used to answer the tap with a bare
/// `toast('Assign course')` and enrol nobody.
///
/// Opens the org roster as a multi-select, posts the chosen ids to
/// `/lms/courses/{id}/assign/`, and reloads the learner records so the new
/// enrolments appear without a restart. People already on the course are
/// pre-ticked and left alone (the server skips them anyway).
///
/// [courseId] may be null on the Learners list, which has no course in scope:
/// the picker then asks for the course first.
Future<void> assignCourse(
  BuildContext context,
  WidgetRef ref, {
  String? courseId,
  String? courseTitle,
}) async {
  final toast = ref.read(toastProvider.notifier);

  var targetId = courseId;
  var targetTitle = courseTitle;
  if (targetId == null || targetId.isEmpty) {
    final courses = ref.read(lmsCoursesProvider);
    if (courses.isEmpty) {
      toast.show('No courses to assign yet');
      return;
    }
    final picked = await showOptionPicker(
      context: context,
      title: 'Which course?',
      options: [
        for (final c in courses) CatalogOption(id: c.id, name: c.title)
      ],
      selected: {courses.first.id},
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    targetId = picked.first;
    targetTitle = courses.firstWhere((c) => c.id == targetId).title;
  }

  // Everyone already enrolled, so the picker opens showing the current state
  // rather than an empty list that implies nobody is on the course.
  final List<LearnerRecord> onCourse =
      ref.read(lmsCourseLearnersProvider(targetId)).valueOrNull ??
          ref.read(lmsRecordsProvider);
  final already = <String>{
    for (final r in onCourse)
      if (r.courses.any((e) => e.courseId == targetId))
        if (UserDirectory.realUserId(r.rid) case final id?) id,
  };

  final roster = ref.read(rosterProvider);
  if (roster.isEmpty) {
    toast.show("Couldn't load the org's members");
    return;
  }
  final chosen = await showOptionPicker(
    context: context,
    title: 'Assign ${targetTitle ?? 'course'} to',
    multi: true,
    options: [
      for (final u in roster)
        if (UserDirectory.realUserId(u.id) case final id?)
          CatalogOption(id: id, name: u.name),
    ],
    selected: already,
  );
  if (chosen == null || !context.mounted) return;

  final newIds = chosen.difference(already).toList();
  if (newIds.isEmpty) {
    toast.show('Everyone selected is already on this course');
    return;
  }

  try {
    final enrolled = await ref
        .read(lmsRepositoryProvider)
        .assignCourse(courseId: targetId, userIds: newIds);
    if (!context.mounted) return;
    toast.show(enrolled == 1
        ? 'Course assigned to 1 learner'
        : 'Course assigned to $enrolled learners');
    // The detail's tiles, the learner rows and the overview's activity feed
    // all read from these.
    reloadLms(ref);
  } on AppError catch (e) {
    if (context.mounted) toast.showError(e.message);
  }
}

/// Sends a real reminder to [rid] (a roster id, possibly the `me` sentinel)
/// about [courseId], then toasts. Shared by the three Nudge buttons, which
/// used to toast "Reminder sent" without sending anything.
Future<void> nudgeLearner(
  BuildContext context,
  WidgetRef ref, {
  required String rid,
  required String courseId,
  required String firstName,
}) async {
  final toast = ref.read(toastProvider.notifier);
  final userId = UserDirectory.realUserId(rid);
  if (userId == null || courseId.isEmpty) {
    toast.show("Couldn't send — learner or course not resolved");
    return;
  }
  try {
    await ref
        .read(lmsRepositoryProvider)
        .nudgeLearner(userId: userId, courseId: courseId);
    if (context.mounted) toast.show('Reminder sent to $firstName');
  } on AppError catch (e) {
    if (context.mounted) toast.showError(e.message);
  }
}

/// The webapp's Assign course modal for the Learners list and the learner
/// detail: published courses only, labelled "<title> · <N> modules", posted to
/// `/lms/learners/assign/` with an optional deadline. [only] limits the
/// learners to one person, pre-ticked (the learner detail).
Future<void> assignFromLearners(BuildContext context, WidgetRef ref,
    {AssignableUser? only}) async {
  // Read fresh: the list may never have loaded on this path, and a course
  // published or moved to draft elsewhere must show (or not) right away.
  await ref.read(lmsCoursesControllerProvider.notifier).reload();
  if (!context.mounted) return;
  final published = [
    for (final c in ref.read(lmsCoursesProvider))
      if (c.isPublished) c
  ];
  final r = await showAssignCourseSheet(
    context,
    courses: [
      for (final c in published) (c.id, '${c.title} · ${c.moduleTotal} modules')
    ],
    learners: only == null ? null : [only],
    preselect: only?.id,
  );
  if (r == null) return;
  final title = published
          .where((c) => c.id == r.courseId)
          .map((c) => c.title)
          .firstOrNull ??
      r.courseTitle;
  ref.read(toastProvider.notifier).show(
      '"$title" assigned to ${r.enrolled} learner${r.enrolled == 1 ? '' : 's'}');
  reloadLms(ref);
}

/// Webapp list / detail Nudge: `POST /lms/learners/{id}/nudge/` with no course,
/// so the learner is reminded about all of their courses.
Future<void> nudgeAllCourses(BuildContext context, WidgetRef ref,
    {required String userId, required String name}) async {
  final toast = ref.read(toastProvider.notifier);
  try {
    await ref.read(courseAdminRemoteProvider).nudge(userId);
    if (context.mounted) toast.show('Reminder sent to $name');
  } on AppError catch (e) {
    if (context.mounted) toast.showError(e.message);
  }
}
