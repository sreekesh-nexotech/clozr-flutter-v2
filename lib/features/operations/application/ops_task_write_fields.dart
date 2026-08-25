import 'package:flutter/material.dart' show TimeOfDay;

import '../../../data/api/user_directory.dart';
import '../../crm/domain/entities/crm_catalog.dart';
import 'project_write_fields.dart' show apiDate;

/// Builds the `/projects/tasks/` write body from what the task form collects
/// (`operations-task.md` §5, `operations.md` §13.1).
///
/// Shared by create and edit so the two can never drift into sending different
/// keys for the same field — the create form used to post four keys while
/// collecting eleven, so the assignees, status, task group, both dates, both
/// times and the expected hours were gathered from the user and dropped.
///
/// ⚠️ Unknown keys are **silently ignored** by this API, so a wrong name looks
/// like it saved. Every key below is one the docs name explicitly.
Map<String, dynamic> opsTaskWriteFields({
  required String subject,
  required String priority,
  required String description,
  String? projectId,
  String? groupId,
  String? statusLabel,
  Set<String> assigneeIds = const {},
  DateTime? start,
  TimeOfDay? startTime,
  DateTime? end,
  TimeOfDay? endTime,
  String expectedHours = '',
  String weight = '',
  List<CatalogOption> statuses = const [],
}) {
  // 'me' is a UI sentinel, never a real id — realUserId turns it back into the
  // signed-in user's UUID and rejects prototype ids outright.
  final assignees = [
    for (final id in assigneeIds)
      if (UserDirectory.realUserId(id) case final real?) real,
  ];
  // An empty result from a non-empty selection means every id was unusable;
  // sending `[]` would then read as "clear the assignees" rather than "leave
  // them alone".
  final assigneesUsable = assigneeIds.isEmpty || assignees.isNotEmpty;

  return {
    'subject': subject.trim(),
    'priority': priority,
    'description': description.trim(),
    if (projectId != null && projectId.isNotEmpty) 'project': projectId,
    // "No group" is simply omitted: the FK is nullable and defaults to null, so
    // a create needs no key for it. Note that *clearing* a lane on an existing
    // task would need an explicit null, which the data source's `_clean` strips
    // — worth revisiting if the edit form grows a "move to No group".
    if (groupId != null && groupId.isNotEmpty) 'task_group': groupId,
    if (_idFor(statuses, statusLabel) case final id?) 'status': id,
    if (assigneesUsable) 'assignees': assignees,
    if (_stamp(start, startTime) case final v?) 'exp_start_date': v,
    if (_stamp(end, endTime) case final v?) 'exp_end_date': v,
    // Both forms collected these and neither sent them, so "Expected time" and
    // "Task weight" were typed, saved, and silently discarded. Decimals on the
    // wire, so they go out as numbers rather than the raw text.
    if (_number(expectedHours) case final v?) 'expected_time': v,
    if (_number(weight) case final v?) 'task_weight': v,
  };
}

/// A numeric form field as the API wants it, or null when it is blank or not a
/// number — in which case the key is omitted and the stored value stands,
/// rather than a typo clearing it.
num? _number(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  return num.tryParse(t);
}

/// A date plus its optional time, as a UTC instant (`…T12:00:00Z`).
///
/// The picker gives a local wall-clock time. Sending those digits *unlabelled*
/// leaves the server to guess the zone: with `USE_TZ` and a UTC server, 5:30 PM
/// IST is stored as 5:30 PM **UTC**, then read back and converted to local as
/// 11:00 PM — the time you typed is not the time you see. Converting to UTC
/// first pins the actual instant, and the read path's `toLocal()` turns it back
/// into the same 5:30 PM.
String? _stamp(DateTime? date, TimeOfDay? time) {
  if (date == null) return null;
  final t = time ?? const TimeOfDay(hour: 0, minute: 0);
  final local = DateTime(date.year, date.month, date.day, t.hour, t.minute);
  final utc = local.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${apiDate(utc)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}

/// Resolves a picked label to the org's own catalog id. Null (skip the key)
/// when there is no label or nothing matches — the API defaults a missing
/// `status` to the org's default, which beats sending a guess.
String? _idFor(List<CatalogOption> catalog, String? label) {
  final needle = label?.trim().toLowerCase();
  if (needle == null || needle.isEmpty) return null;
  for (final o in catalog) {
    if (o.name.trim().toLowerCase() == needle) return o.id;
  }
  return null;
}
