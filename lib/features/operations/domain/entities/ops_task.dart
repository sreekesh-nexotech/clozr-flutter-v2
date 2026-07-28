import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// A checklist subtask on an [OpsTask].
class Subtask {
  final String title;
  bool done;
  final String who; // user id
  final String due; // display, e.g. "14 May"

  Subtask({required this.title, required this.done, required this.who, required this.due});
}

/// A note left on an entity (project / task).
class OpsNote {
  final String author;
  final String time;
  final String body;

  const OpsNote({required this.author, required this.time, required this.body});
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
  final String pri; // High / Medium / Low
  final List<String> assignees; // user ids
  final bool milestone;
  final String start; // "12 May 2026"
  final String startTime; // "9:00 AM"
  final String end;
  final String endTime;
  final String endISO; // "2026-05-20"
  final int expHrs;
  final int? progress; // null => derive from subtasks
  final int weight;
  final String dept;
  final OpsColorTag color;
  final List<Subtask> subtasks;
  final List<String> waitingOn; // task ids
  final List<OpsNote> notes;
  final String desc;
  final String? actualStart;
  final String? actualEnd;
  final String? actualEndFull;
  final String? fromTicket; // ticket id, if raised from a ticket

  const OpsTask({
    required this.id,
    required this.subject,
    required this.projId,
    required this.group,
    required this.status,
    required this.pri,
    required this.assignees,
    required this.milestone,
    required this.start,
    required this.startTime,
    required this.end,
    required this.endTime,
    required this.endISO,
    required this.expHrs,
    required this.progress,
    required this.weight,
    required this.dept,
    required this.color,
    required this.subtasks,
    required this.waitingOn,
    required this.notes,
    required this.desc,
    this.actualStart,
    this.actualEnd,
    this.actualEndFull,
    this.fromTicket,
  });

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
