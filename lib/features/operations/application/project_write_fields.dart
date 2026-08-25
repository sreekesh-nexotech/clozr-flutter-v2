import '../../../data/api/user_directory.dart';
import '../../crm/domain/entities/crm_catalog.dart';

/// Builds the write body for a project — `POST /projects/projects/` and
/// `PATCH /projects/projects/{id}/`.
///
/// Shared by the create and edit screens because they had drifted into sending
/// **four** keys between them (`project_name`, `priority`, `description`,
/// `expected_end_date`) while both forms collected thirteen. Everything else —
/// the customer, the project type, the manager, the team, the assignees, the
/// cost, the start date, the visibility, the progress method — was gathered
/// from the user and silently dropped.
///
/// Every FK the API takes is a **UUID**, never the label the picker shows
/// (`operations.md` §"All FK inputs … are org-scoped — a UUID from another org
/// (or a stale one) → 400"). So each id is resolved against the org catalog
/// here, and a value that cannot be resolved is **omitted** rather than sent as
/// a name the server would reject.
Map<String, dynamic> projectWriteFields({
  required String name,
  required String priority,
  required String description,
  String? customerLabel,
  String? typeLabel,
  String? statusLabel,
  String? teamLabel,
  String? managerId,
  Set<String> assigneeIds = const {},
  String? cost,
  DateTime? start,
  DateTime? end,
  String? visibility,
  String? progressMethod,
  String? percentComplete,
  List<CatalogOption> customers = const [],
  List<CatalogOption> types = const [],
  List<CatalogOption> statuses = const [],
  List<CatalogOption> teams = const [],
}) {
  final manager = UserDirectory.realUserId(managerId);
  final manualPercent =
      progressMethod?.trim() == 'Manual' ? _percent(percentComplete) : null;

  // Assignees are sent whenever the form has a set to send — including an empty
  // one, which is how the API is told to remove everybody. Guarding on
  // `isNotEmpty` meant deselecting the last assignee saved as "no change".
  //
  // The exception is a set whose ids all failed to resolve: sending `[]` there
  // would wipe the real assignees over a mapping problem, so the key is left
  // out and the stored set is untouched.
  final assignees = [
    for (final id in assigneeIds)
      if (UserDirectory.realUserId(id) case final real?) real,
  ];
  final assigneesUsable = assigneeIds.isEmpty || assignees.isNotEmpty;

  return <String, dynamic>{
    'project_name': name.trim(),
    'priority': priority,
    'description': description.trim(),
    if (start != null) 'expected_start_date': apiDate(start),
    if (end != null) 'expected_end_date': apiDate(end),
    // An empty customer is "internal project", which the API takes as null —
    // distinct from omitting the key, which would leave an existing link alone.
    if (customerLabel != null)
      'customer': customerLabel.isEmpty ? null : _idFor(customers, customerLabel),
    if (_idFor(types, typeLabel) case final id?) 'project_type': id,
    if (_idFor(statuses, statusLabel) case final id?) 'status': id,
    if (teamLabel != null)
      'assigned_team': teamLabel.isEmpty ? null : _idFor(teams, teamLabel),
    if (manager != null) 'manager': manager,
    if (assigneesUsable) 'assignees': assignees,
    if (cost != null && cost.trim().isNotEmpty)
      'estimated_costing': _amount(cost),
    // Fixed enums, lowercase on the wire: the "Organization" option POSTs
    // "organization".
    if (visibility != null && visibility.trim().isNotEmpty)
      'visibility': visibility.trim().toLowerCase(),
    // `percent_complete_method`, not `progress_method`.
    if (progressMethod != null && progressMethod.trim().isNotEmpty)
      'percent_complete_method': progressMethod.trim(),
    // Only ever sent with `Manual`: the API accepts `percent_complete` when
    // the method is Manual and **drops it silently** otherwise, since every
    // other method derives the figure from the tasks. Sending it regardless
    // would look saved and not be.
    if (manualPercent != null) 'percent_complete': manualPercent,
  };
}

/// A typed progress value clamped to 0–100, or null when the box is empty or
/// holds nothing numeric.
String? _percent(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null) return null;
  return value.clamp(0, 100).toStringAsFixed(0);
}

/// `YYYY-MM-DD`, the date form the API takes.
String apiDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The catalog id whose name matches [label], or null when the catalog has not
/// loaded or holds no such entry — the key is then omitted entirely.
String? _idFor(List<CatalogOption> options, String? label) {
  final wanted = (label ?? '').trim().toLowerCase();
  if (wanted.isEmpty) return null;
  for (final o in options) {
    if (o.name.trim().toLowerCase() == wanted) return o.id;
  }
  return null;
}

/// A typed cost as the decimal string the API wants — "₹25,00,000" → "2500000".
String _amount(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9.]'), '');
  return digits.isEmpty ? '0' : digits;
}
