import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/network/app_error.dart';

/// Webapp `projectClose.ts` (UAT D24 / contract C4): moving a project into a
/// closed status while it still has open tasks is refused with
/// `409 {code: "PROJECT_HAS_OPEN_TASKS", open_task_count}`. The user is asked,
/// and on "Close project" the same write is resent with
/// `open_tasks_action: "cancel"` — the server cancels the open tasks and closes
/// the project.
const projectHasOpenTasks = 'PROJECT_HAS_OPEN_TASKS';

/// The body key the confirmed retry carries.
const openTasksActionCancel = {'open_tasks_action': 'cancel'};

/// The open-task conflict [error] describes, or null for any other failure.
/// `count` is null when the server did not say how many.
({int? count})? openTasksConflict(Object error) {
  if (error is! AppError || error.code != projectHasOpenTasks) return null;
  final raw = error.extra?['open_task_count'];
  final n = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
  return (count: n != null && n >= 0 ? n : null);
}

String _phrase(int? count) =>
    count == null ? 'Its open tasks' : '$count open task${count == 1 ? '' : 's'}';

/// "Project closed — 2 open tasks were cancelled".
String closedWithOpenTasksMessage(int? count) => count == null
    ? 'Project closed — its open tasks were cancelled'
    : 'Project closed — ${_phrase(count)} ${count == 1 ? 'was' : 'were'} cancelled';

/// "Close project with open tasks?" — true on "Close project", false/null on
/// "Keep it open" or a dismiss.
Future<bool> confirmCloseWithOpenTasks(BuildContext context, int? count) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Close project with open tasks?'),
      content: Text('${_phrase(count)} will be cancelled. Close the project anyway?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep it open'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Close project', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  return ok == true;
}
