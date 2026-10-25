/// Pure rules behind the **New follow-up** sheet — a port of the webapp's Add
/// follow-up form (`AddTaskModal` with `isFollowup`, `taskCreateForm.ts`,
/// `taskCustomField.ts`, `taskCreate.request.ts`). Kept out of the widget so the
/// validation, the custom-field filtering and the request body are unit-tested
/// and say exactly what the webapp says and sends (UAT CRM-FU-013).
///
/// The webapp form is a FIXED field set — it is not built from the follow-up
/// layout schema — so neither is this one.
library;

// ── Reminder (follow-ups only) ──

/// Webapp `REMINDER_OPTIONS` — the server's `Task.ReminderChoice`.
const followupReminderOptions = <(String, String)>[
  ('15min', '15 minutes before'),
  ('30min', '30 minutes before'),
  ('1hour', '1 hour before'),
  ('2hours', '2 hours before'),
  ('1day', '1 day before'),
  ('2days', '2 days before'),
];

bool isReminderChoice(String value) => followupReminderOptions.any((o) => o.$1 == value);

/// The label a reminder value shows as; "No reminder" when blank / unknown.
String reminderLabel(String value) =>
    followupReminderOptions.where((o) => o.$1 == value).firstOrNull?.$2 ?? 'No reminder';

const reminderNeedsDueDateMessage = 'A due date is required when setting a reminder.';

// ── Field limits and wording ──

/// Server `Task.title` max length.
const followupTitleMax = 280;

/// Webapp `Location` input `maxLength`.
const followupLocationMax = 280;

/// Single-line custom text limit (webapp `TEXT_MAX_LENGTH`).
const customTextMax = 255;

// ── Due date (TK-04) ──

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Earliest due date the form accepts (webapp `DUE_DATE_MIN`).
final followupDueDateMin = DateTime(2000, 1, 1);

/// Latest due date: today + 5 years (webapp `dueDateBounds`).
DateTime followupDueDateMax([DateTime? today]) {
  final t = today ?? DateTime.now();
  return DateTime(t.year + 5, t.month, t.day);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `08-Dec-2025` — the webapp's `displayDay` / `fmtCalendarDay`.
String followupDayLabel(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${_months[d.month - 1]}-${d.year}';

/// `2026-06-24` — the form the API stores.
String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Webapp `dueDateError`: why a due date cannot be saved, or null.
String? followupDueDateError(DateTime? due, {DateTime? today}) {
  if (due == null) return null;
  final d = _day(due);
  if (d.isBefore(followupDueDateMin)) {
    return "The due date can't be before ${followupDayLabel(followupDueDateMin)}.";
  }
  final max = followupDueDateMax(today);
  if (d.isAfter(max)) {
    return "The due date can't be more than 5 years ahead (latest ${followupDayLabel(max)}).";
  }
  return null;
}

/// Webapp `isPastDueDate`: the follow-up would be overdue as soon as it exists.
bool isPastDueDate(DateTime? due, {DateTime? today}) =>
    due != null && _day(due).isBefore(_day(today ?? DateTime.now()));

// ── Meeting window ──

/// Webapp `isMeetingType`: a meeting type opens the meeting fields by default.
bool isMeetingType(String type) => RegExp('meet', caseSensitive: false).hasMatch(type);

const meetingOrderMessage = 'Meeting end cannot be before the meeting start.';

/// Webapp `meetingWindowError`: the meeting cannot end before it starts.
String? meetingWindowError(DateTime? from, DateTime? to) =>
    from != null && to != null && to.isBefore(from) ? meetingOrderMessage : null;

// ── Custom fields (CF-01) ──

/// A task custom-field definition (`GET /management/custom-fields/?model_name=task`).
/// Tasks and follow-ups share one schema; [appliesTo] (`all` | `task` |
/// `followup`) says which kind of record a field belongs on.
class TaskCustomFieldDef {
  const TaskCustomFieldDef({
    required this.id,
    required this.name,
    required this.label,
    required this.type,
    this.required = false,
    this.choices = const [],
    this.order = 0,
    this.appliesTo = 'all',
  });

  final String id;

  /// Key inside a record's `custom_fields` (the definition's `field_name`).
  final String name;
  final String label;

  /// `text` | `textarea` | `number` | `decimal` | `date` | `datetime` |
  /// `boolean` | `dropdown` | `multi_select` | `email` | `phone` | `url`.
  final String type;
  final bool required;

  /// Dropdown / multi-select options; the value IS the label.
  final List<String> choices;
  final int order;
  final String appliesTo;

  static const _types = {
    'text', 'textarea', 'number', 'decimal', 'date', 'datetime', //
    'boolean', 'dropdown', 'multi_select', 'email', 'phone', 'url',
  };

  /// One wire row, or null when it is inactive or unusable. Tolerant like the
  /// webapp's DTO: an unknown type reads as `text`, a missing `applies_to` as
  /// `all`.
  static TaskCustomFieldDef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['is_active'] == false) return null;
    final id = '${raw['custom_field_id'] ?? raw['id'] ?? ''}';
    final name = '${raw['field_name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    final label = '${raw['label'] ?? ''}'.trim();
    final type = '${raw['field_type'] ?? ''}';
    final applies = '${raw['applies_to'] ?? ''}';
    final choices = <String>[];
    final rawChoices = raw['choices'];
    if (rawChoices is List) {
      for (final c in rawChoices) {
        Object? v = c;
        if (c is Map) v = c['value'] ?? c['label'];
        if (v is String || v is num) {
          final s = '$v';
          if (s.isNotEmpty && !choices.contains(s)) choices.add(s);
        }
      }
    }
    return TaskCustomFieldDef(
      id: id,
      name: name,
      label: label.isEmpty || label == 'null' ? name : label,
      type: _types.contains(type) ? type : 'text',
      required: raw['is_required'] == true,
      choices: choices,
      order: (raw['order'] as num?)?.toInt() ?? 0,
      appliesTo: applies == 'task' || applies == 'followup' ? applies : 'all',
    );
  }

  /// A DRF page (`{results: [...]}`) or a bare list → active definitions in
  /// display order.
  static List<TaskCustomFieldDef> listFromResponse(Object? body) {
    final rows = body is Map ? body['results'] : body;
    if (rows is! List) return const [];
    final out = rows.map(fromJson).whereType<TaskCustomFieldDef>().toList();
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }
}

/// Webapp `customFieldsForKind`: the fields of one record kind (`all` + the
/// kind's own), in the admin's display order.
List<TaskCustomFieldDef> customFieldsForKind(List<TaskCustomFieldDef> defs, {required bool isFollowup}) {
  final kind = isFollowup ? 'followup' : 'task';
  final out = [for (final d in defs) if (d.appliesTo == 'all' || d.appliesTo == kind) d];
  out.sort((a, b) => a.order.compareTo(b.order));
  return out;
}

/// The value a custom field starts with: `false` for a checkbox, an empty list
/// for a multi-select, `''` otherwise.
Object emptyCustomDraft(TaskCustomFieldDef def) => switch (def.type) {
      'boolean' => false,
      'multi_select' => const <String>[],
      _ => '',
    };

const customRequiredMessage = 'This field is required.';
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _urlRe = RegExp(r'^https?://', caseSensitive: false);
final _isoDayRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _dateTimeRe = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

bool _validIsoDay(String s) {
  final m = _isoDayRe.firstMatch(s);
  if (m == null) return false;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final dt = DateTime(y, mo, d);
  return dt.month == mo && dt.day == d;
}

/// One field's wire value or error (webapp `shape`). `value == null` and no
/// error = nothing to send.
({Object? value, String? error}) _shape(TaskCustomFieldDef def, Object? draft) {
  if (def.type == 'boolean') return (value: draft == true, error: null);
  if (def.type == 'multi_select') {
    final picked = [
      if (draft is List)
        for (final v in draft)
          if (def.choices.contains(v)) '$v',
    ];
    if (picked.isEmpty) return (value: null, error: def.required ? customRequiredMessage : null);
    return (value: picked, error: null);
  }
  final text = draft is String ? draft.trim() : '';
  if (text.isEmpty) return (value: null, error: def.required ? customRequiredMessage : null);
  switch (def.type) {
    case 'number':
    case 'decimal':
      final n = num.tryParse(text);
      return n != null && n.isFinite ? (value: n, error: null) : (value: null, error: 'Must be a numeric value.');
    case 'date':
      return _validIsoDay(text) ? (value: text, error: null) : (value: null, error: 'Must be a date (YYYY-MM-DD).');
    case 'datetime':
      return _dateTimeRe.hasMatch(text) ? (value: text, error: null) : (value: null, error: 'Must be a date and time.');
    case 'dropdown':
      return def.choices.contains(text) ? (value: text, error: null) : (value: null, error: 'Pick one of the options.');
    case 'email':
      return _emailRe.hasMatch(text) ? (value: text, error: null) : (value: null, error: 'Must be a valid email address.');
    case 'url':
      return _urlRe.hasMatch(text)
          ? (value: text, error: null)
          : (value: null, error: 'Must be a valid URL (http:// or https://).');
    case 'text':
      return text.length > customTextMax
          ? (value: null, error: 'Must be at most $customTextMax characters.')
          : (value: text, error: null);
    default:
      return (value: text, error: null);
  }
}

/// Webapp `collectCustomFields`: validate the form's custom fields and shape
/// them for the POST. Blank optional fields are left out; required ones are
/// reported by field name.
({Map<String, Object> values, Map<String, String> errors}) collectCustomFields(
    List<TaskCustomFieldDef> defs, Map<String, Object?> drafts) {
  final values = <String, Object>{};
  final errors = <String, String>{};
  for (final def in defs) {
    final r = _shape(def, drafts[def.name]);
    if (r.error != null) {
      errors[def.name] = r.error!;
    } else if (r.value != null) {
      values[def.name] = r.value!;
    }
  }
  return (values: values, errors: errors);
}

// ── The form ──

/// Error-map key of a custom field (kept apart from the standard fields).
String customErrorKey(String name) => 'custom_fields.$name';

/// What the user has filled in. Ids are the server's (`status_id`,
/// `task_priority_id`, `team_id`, `user_id`); [type] is the follow-up type's
/// **name**, which is how a follow-up's `task_type` is written.
class FollowupDraft {
  const FollowupDraft({
    this.title = '',
    this.type = '',
    this.statusId = '',
    this.priorityId = '',
    this.assignedTo = '',
    this.extraAssignees = const [],
    this.teamId = '',
    this.dueDate,
    this.dueTime = '',
    this.reminder = '',
    this.meetingFrom,
    this.meetingTo,
    this.location = '',
    this.description = '',
    this.relatedTo = '',
    this.relatedToId = '',
  });

  final String title;
  final String type;
  final String statusId;
  final String priorityId;

  /// The primary owner; `''` = Unassigned.
  final String assignedTo;

  /// Extra assignees beyond the primary.
  final List<String> extraAssignees;
  final String teamId;
  final DateTime? dueDate;

  /// `HH:MM`; only sent with a due date.
  final String dueTime;
  final String reminder;
  final DateTime? meetingFrom;
  final DateTime? meetingTo;
  final String location;
  final String description;

  /// `lead` | `customer` | `''`.
  final String relatedTo;
  final String relatedToId;
}

/// Webapp `canSave`: a title and a type (and the custom fields known, which the
/// sheet checks itself).
bool followupCanSave(FollowupDraft d) => d.title.trim().isNotEmpty && d.type.isNotEmpty;

/// The webapp's save-time checks, keyed `dueDate` / `reminder` / `meetingTo` /
/// `custom_fields.<name>`. Empty = good to go (subject to the overdue confirm).
Map<String, String> followupFormErrors(FollowupDraft d, List<TaskCustomFieldDef> customDefs,
    Map<String, Object?> customDrafts,
    {DateTime? today}) {
  final found = <String, String>{};
  final due = followupDueDateError(d.dueDate, today: today);
  if (due != null) found['dueDate'] = due;
  if (d.reminder.isNotEmpty && d.dueDate == null) found['reminder'] = reminderNeedsDueDateMessage;
  final meeting = meetingWindowError(d.meetingFrom, d.meetingTo);
  if (meeting != null) found['meetingTo'] = meeting;
  for (final e in collectCustomFields(customDefs, customDrafts).errors.entries) {
    found[customErrorKey(e.key)] = e.value;
  }
  return found;
}

/// `POST /crm/tasks/` body — webapp `AddTaskModal.save` + `toCreateTaskBody`.
/// Blank optionals are left out (the server applies its defaults); the due
/// time and the reminder only ride with a due date; `assignees` only when the
/// set (primary + extras) holds more than one user, exactly as the webapp does.
Map<String, dynamic> buildFollowupCreateBody(FollowupDraft d, Map<String, Object> customValues) {
  final due = d.dueDate;
  final primary = d.assignedTo;
  final assignees = [if (primary.isNotEmpty) primary, ...d.extraAssignees];
  final location = d.location.trim();
  final description = d.description.trim();
  return {
    'title': d.title.trim(),
    'task_type': d.type,
    'is_followup': true,
    if (due != null) 'due_date': isoDay(due),
    if (due != null && d.dueTime.isNotEmpty) 'due_time': d.dueTime,
    if (description.isNotEmpty) 'description': description,
    if (primary.isNotEmpty) 'assigned_to': primary,
    if (assignees.length > 1) 'assignees': assignees,
    if (d.teamId.isNotEmpty) 'assigned_team': d.teamId,
    if (d.statusId.isNotEmpty) 'status_id': d.statusId,
    if (d.priorityId.isNotEmpty) 'priority': d.priorityId,
    if (d.relatedTo.isNotEmpty && d.relatedToId.isNotEmpty) ...{
      'related_to': d.relatedTo,
      'related_to_id': d.relatedToId,
    },
    if (due != null && isReminderChoice(d.reminder)) 'reminder_choice': d.reminder,
    if (d.meetingFrom != null) 'meeting_from': d.meetingFrom!.toUtc().toIso8601String(),
    if (d.meetingTo != null) 'meeting_to': d.meetingTo!.toUtc().toIso8601String(),
    if (location.isNotEmpty) 'location': location,
    if (customValues.isNotEmpty) 'custom_fields': Map<String, Object>.of(customValues),
  };
}
