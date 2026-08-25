import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// A checklist subtask on an [OpsTask].
///
/// On the API a subtask **is a task** — a `projects.Task` with `parent_task`
/// set (`operations-task.md` §3C) — so it has its own `task_id`, which is what
/// a tick PATCHes. [id] is empty only for the prototype seed, where the
/// checklist is a plain in-memory list with nothing to write to.
class Subtask {
  final String id;
  final String title;
  bool done;
  final String who; // user id
  final String due; // display, e.g. "14 May"

  Subtask({
    this.id = '',
    required this.title,
    required this.done,
    required this.who,
    required this.due,
  });
}

/// A decimal field as the UI shows it: "24", "3.5" — the API sends these as
/// fixed-point strings ("24.000000"), and "24.0 hrs" reads like a rounding
/// artefact rather than a number someone typed.
String opsDecimalLabel(double v) =>
    v == v.roundToDouble() ? v.round().toString() : '$v';

/// A note left on an entity (project / task).
class OpsNote {
  final String author;
  final String time;
  final String body;

  const OpsNote({required this.author, required this.time, required this.body});
}

/// One edge of a task dependency, resolved server-side.
///
/// The detail retrieve labels both directions itself (`operations-task.md` §3:
/// "Dependency labels come free on detail — don't resolve blocker UUIDs against
/// `/tasks/` one by one"), so a chip needs no second fetch and no scan of the
/// full task list.
class TaskDep {
  const TaskDep({
    required this.edgeId,
    required this.taskId,
    required this.subject,
    this.statusName = '',
    this.isClosed = false,
  });

  /// `task_depends_on_id` — the edge itself, which is what a DELETE removes.
  final String edgeId;

  /// `task_id` — the *other* task in the edge, not this one.
  final String taskId;
  final String subject;
  final String statusName;
  final bool isClosed;
}

/// A colour tag on an [OpsTask] (`{ name, hex }` in the prototype).
class OpsColorTag {
  final String name;
  final Color hex;

  const OpsColorTag(this.name, this.hex);
}

/// An Operations task. Fields mirror the prototype's `OTSEED` records so the
/// mock data source maps directly and the shape stays API-ready.
class OpsTask extends Equatable {
  final String id;
  final String subject;
  final String projId;
  final String group;
  final String status; // key into StatusMeta$.opsTask

  /// The org's own status name ("In Progress", "Awaiting Sign-off"), as
  /// `/projects/tasks/` reports it in `status_name`.
  ///
  /// Kept beside the folded [status] because the two answer different questions:
  /// [status] picks the colour and the built-in vocabulary, this is what the org
  /// calls it — and what the status tabs and the drawer facet match on now that
  /// both come from `/projects/project-task-statuses/`.
  final String statusName;
  /// The project's name as the row itself reports it (`project_name`).
  ///
  /// Carried here rather than resolved from the loaded project list: a task can
  /// belong to a project that list has not loaded, and a standalone task has no
  /// project at all. Empty means standalone (or mock mode).
  final String projectName;

  /// `task_group` UUID — what the lane picker selects by and what `task_group`
  /// wants on write. [group] is its display name.
  final String groupId;

  /// `task_type_id` UUID and its `task_type_name` label.
  ///
  /// Both are needed: the drawer shows the name, but `type__in` wants the id.
  final String typeId;
  final String typeName;

  /// Detail-only, already labelled: the tasks this one waits on (`dependencies`)
  /// and the ones waiting on it (`dependents`).
  final List<TaskDep> deps;
  final List<TaskDep> blocking;

  /// `task_code` — the display id ("PRJ-1010-t3"), minted per project.
  ///
  /// Empty for a standalone task, a project whose code was never minted, and
  /// every slim list row; the UUID is the fallback and stays the lookup key
  /// either way (`operations-task.md` §3).
  final String code;

  /// `subtask_count` — how many subtasks the server says this task has.
  ///
  /// The subtask rows themselves are a separate fetch (`?parent=<task_id>`,
  /// §3C), so this count is what the card shows until they arrive.
  final int subtaskCount;

  /// `subtask_done_count` — the left half of the "N/M done" counter. Counts
  /// direct subtasks sitting in a **closed** status (detail-only).
  final int subtaskDoneCount;

  /// `pending_dependency_count` — the "Waiting on N" badge.
  ///
  /// Slim list rows carry this count but not the dependency edges, so it is the
  /// only way the list can show the badge; [waitingOn] fills in on detail.
  final int pendingDeps;

  /// The server's own overdue verdict (`is_overdue`), which knows the real date
  /// and the org's closed statuses. Null in mock mode, where the caller falls
  /// back to comparing against the prototype clock.
  final bool? isOverdue;
  final String pri; // High / Medium / Low
  final List<String> assignees; // user ids
  final bool milestone;
  final String start; // "12 May 2026"
  final String startTime; // "9:00 AM"
  final String end;
  final String endTime;
  final String endISO; // "2026-05-20"
  /// `expected_time` and `task_weight` — decimals on the **full** object only
  /// (`?view=list` drops both), which is why they are nullable: a slim row has
  /// no value to show, as opposed to a value of zero.
  ///
  /// Both are fractional on the wire ("24.000000", "3.500000"), so they are
  /// doubles here — a weight of 3.5 rounded to 3 would be a silent edit.
  final double? expHrs;
  final int? progress; // null => derive from subtasks
  final double? weight;
  final String dept;
  final OpsColorTag color;
  final List<Subtask> subtasks;
  final List<String> waitingOn; // task ids
  final List<OpsNote> notes;
  final String desc;
  final String? actualStart;
  final String? actualEnd;
  final String? actualEndFull;

  /// When the task was actually completed, as the API sent it
  /// (`act_end_date`, falling back to `completed_on`). Kept beside the display
  /// forms above because comparing it to [endISO] is what says whether the task
  /// landed before or after its due date.
  final String? actualEndISO;
  final String? fromTicket; // ticket id, if raised from a ticket

  const OpsTask({
    required this.id,
    required this.subject,
    required this.projId,
    required this.group,
    required this.status,
    this.statusName = '',
    this.projectName = '',
    this.groupId = '',
    this.typeId = '',
    this.typeName = '',
    this.deps = const [],
    this.blocking = const [],
    this.code = '',
    this.subtaskCount = 0,
    this.subtaskDoneCount = 0,
    this.pendingDeps = 0,
    this.isOverdue,
    required this.pri,
    required this.assignees,
    required this.milestone,
    required this.start,
    required this.startTime,
    required this.end,
    required this.endTime,
    required this.endISO,
    this.expHrs,
    required this.progress,
    this.weight,
    required this.dept,
    required this.color,
    required this.subtasks,
    required this.waitingOn,
    required this.notes,
    required this.desc,
    this.actualStart,
    this.actualEnd,
    this.actualEndFull,
    this.actualEndISO,
    this.fromTicket,
  });

  /// Whether this task was completed after its due date. Null when either date
  /// is missing — "not known", which is not the same as "on time".
  bool? get completedLate {
    final actual = DateTime.tryParse(actualEndISO ?? '');
    final due = DateTime.tryParse(endISO);
    if (actual == null || due == null) return null;
    // Whole days: a task due today and finished at 6pm is not late.
    return DateTime(actual.year, actual.month, actual.day)
        .isAfter(DateTime(due.year, due.month, due.day));
  }

  bool get isMine => assignees.contains('me');

  bool get isLocked => status == 'completed' || status == 'cancelled';

  bool get hasFromTicket => fromTicket != null && fromTicket!.isNotEmpty;

  int get doneSubs => subtasks.where((s) => s.done).length;

  /// Progress: explicit, else derived from subtask completion.
  int computedProgress(List<Subtask> subs) {
    if (progress != null) return progress!;
    if (subs.isEmpty) return 0;
    return (subs.where((s) => s.done).length / subs.length * 100).round();
  }

  @override
  List<Object?> get props => [id];
}
