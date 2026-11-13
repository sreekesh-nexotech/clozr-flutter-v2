import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../shell/application/providers/shell_providers.dart';
import '../application/providers/lms_providers.dart';
import '../domain/entities/course.dart';

/// Webapp course delete: confirm first, then `DELETE /lms/courses/{id}/`.
/// "Course deleted" only once the server agreed; a refusal is reported by the
/// shell's failure toast with the server's own words. True when deleted.
Future<bool> deleteCourseWithConfirm(
        BuildContext context, WidgetRef ref, Course course) =>
    deleteCourseByIdWithConfirm(context, ref,
        id: course.id, title: course.title);

/// [deleteCourseWithConfirm] for a caller that holds only the id and title
/// (the course editor reads its own payload, not the list entity).
Future<bool> deleteCourseByIdWithConfirm(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String title,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "$title"?'),
      content: const Text(
          'Learners lose access and their progress in this course is removed. '
          'This action cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Delete', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ref.read(lmsRepositoryProvider).deleteCourse(id);
  } on Object {
    return false;
  }
  ref.read(toastProvider.notifier).showInfo('Course deleted');
  ref.read(lmsCoursesControllerProvider.notifier).reload();
  return true;
}
