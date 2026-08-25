import '../../../core/utils/relative_time.dart';
import '../domain/entities/view_schema.dart';

/// Rendering an org-configured layout over a **raw** record row.
///
/// The schema says which columns to show and what type each is; the record is
/// untyped JSON keyed by field name. This turns the two into label/value pairs
/// a detail panel can render, without the screen needing to know which fields
/// its module happens to have.
///
/// Deliberately module-agnostic: Tasks use it today, and the same pairing of
/// `/schema/?view_type=detail` + `GET /<module>/{id}/` drives every other CRM
/// detail page.

/// One rendered row of a detail panel.
///
/// Carries the column [name] alongside the display pair so the screen can key
/// presentation off the field — an icon, a tap target — without matching on the
/// label, which is org-editable text.
typedef RecordRow = ({
  String name,
  String label,
  String value,
  /// The column behind the row, so a detail screen can offer to edit it: the
  /// column is what names the API field, gives its type, and says whether it
  /// is writable at all.
  ViewColumn column,
});

/// The column types a detail row can edit **in place**.
///
/// A foreign key, a date, a boolean or a choice needs a picker to produce a
/// value the API accepts, and a text box in the middle of a readout is not
/// that — those rows stay read-only rather than inviting input the write would
/// reject.
const Set<String> kInlineEditableTypes = {
  'string', 'email', 'url', 'phone', 'text',
  'decimal', 'integer', 'number', 'float',
};

/// Whether long-pressing this row should turn it into a text box.
///
/// Narrower than [ViewColumn.isEditable], which answers "can a form write it":
/// this also needs the value to be typeable, so a status or an owner is
/// excluded even though the full edit form handles both.
bool fieldEditsInline(ViewColumn column) =>
    column.isEditable &&
    !column.hasChoices &&
    kInlineEditableTypes.contains(column.type);

/// Why a long press on this row did not open a box, phrased for the person who
/// pressed it. Null when the row *is* editable in place.
///
/// A gesture that silently does nothing reads as a missed press, so every row
/// answers — the ones that cannot be edited say which kind of "cannot" it is,
/// and [editForm] names where the field can be changed instead.
String? inlineEditHint(ViewColumn? column, {required String editForm}) {
  if (column == null) {
    // No org layout loaded: nothing names the API field or its type.
    return 'This field cannot be edited here.';
  }
  if (fieldEditsInline(column)) return null;
  if (column.isCustom) {
    return '${column.label} is a custom field and cannot be edited in the app yet.';
  }
  if (!column.isEditable) return '${column.label} is read-only.';
  return '${column.label} is chosen from a list — use $editForm to change it.';
}

/// The rows to render: **every** visible column, in the org's order and under
/// the org's labels.
///
/// Deliberately exhaustive — the panel is a complete readout of the org's
/// detail layout, not a summary of it:
///
/// * A column the record has **no value** for still renders, as `—`: layout and
///   payload come from the same detail config, so an empty value means the
///   record genuinely has none, which on a detail page is information.
/// * A column the row does not carry **at all** also renders as `—`. Payload
///   and layout disagreeing is worth surfacing as "nothing to show here", where
///   dropping the row hides the disagreement entirely.
/// * Columns the page also renders in its own chrome are **not** excluded by
///   default. Pass [skip] only where a caller genuinely wants a column left
///   out; the chrome is unaffected either way.
List<RecordRow> recordRows(
  Map<String, dynamic> row,
  ViewSchema schema, {
  Set<String> skip = const {},
}) {
  final out = <RecordRow>[];
  for (final column in schema.columns) {
    if (skip.contains(column.name)) continue;
    final raw = column.isCustom
        ? _customValue(row, column.customKey)
        : (row.containsKey(column.name) ? row[column.name] : _absent);
    out.add((
      name: column.name,
      label: column.label,
      column: column,
      // The absent sentinel is not a value the formatter should see; a column
      // the payload omits reads the same as one it sent empty.
      value: identical(raw, _absent) ? _dash : recordValueText(raw, column.type),
    ));
  }
  return out;
}

/// Sentinel for "the row has no such key", distinct from a key present as null.
const Object _absent = Object();

Object? _customValue(Map<String, dynamic> row, String key) {
  final custom = row['custom_fields'];
  if (custom is! Map || !custom.containsKey(key)) return _absent;
  return custom[key];
}

/// Formats one value for display, using the type the schema reported.
///
/// Returns `—` rather than an empty string: a detail row with nothing after its
/// label reads as a rendering bug, where an em dash reads as "we have none".
String recordValueText(Object? value, String type) {
  if (value == null) return _dash;

  switch (type) {
    case 'date':
      final date = parseApiDate(value);
      return date != null ? absoluteDate(date) : _plain(value);
    case 'datetime':
      final at = parseApiDate(value);
      return at != null ? '${absoluteDate(at)} · ${relativeTime(at)}' : _plain(value);
    case 'time':
      // `HH:MM:SS` → `HH:MM`; a task's due time never needs seconds.
      final text = '$value'.trim();
      final parts = text.split(':');
      return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : _plain(value);
    case 'boolean':
      return value == true ? 'Yes' : 'No';
    case 'integer':
    case 'number':
    case 'decimal':
      return _plain(value);
    default:
      return _plain(value);
  }
}

const String _dash = '—';

/// Untyped formatting, which also covers the shapes a *type* cannot describe:
/// a foreign key arriving as a nested object, a many-to-many as a list of them.
String _plain(Object? value) {
  if (value == null) return _dash;

  // A foreign key: `{name: "High"}`, `{full_name: "Admin Acme"}`, or the
  // `related_to` block, which names the record it points at.
  if (value is Map) {
    for (final key in const [
      'name',
      'full_name',
      'title',
      'lead_name',
      'label',
      'display',
    ]) {
      final v = value[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return _dash;
  }

  if (value is List) {
    final parts = [
      for (final v in value)
        if (_plain(v) != _dash) _plain(v),
    ];
    return parts.isEmpty ? _dash : parts.join(', ');
  }

  if (value is bool) return value ? 'Yes' : 'No';

  if (value is num) {
    // Whole decimals arrive as `30.0`; a trailing `.0` reads as noise.
    final text = value.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  final text = '$value'.trim();
  return text.isEmpty ? _dash : text;
}

/// The value to send for a text-entered schema field, by its column type.
///
/// Pure so it can be tested without pumping a form — and because getting it
/// wrong is a whole-form failure, not a cosmetic one: sending a number field's
/// box as text meant an untouched `duration` arrived as `""` and the API
/// rejected the entire save with
/// `{"duration": ["A valid integer is required."]}`.
///
/// Returns [absentValue] when the key should be **omitted** — distinct from
/// `null`, which clears the field.
Object? schemaWriteValue(String type, String text) {
  final trimmed = text.trim();
  switch (type) {
    case 'integer':
    case 'decimal':
    case 'number':
      if (trimmed.isEmpty) return null; // emptied on purpose → clear it
      final n = type == 'integer' ? int.tryParse(trimmed) : num.tryParse(trimmed);
      // Unparseable is not an instruction to clear; leave the stored value be
      // rather than 400 or wipe it.
      return n ?? absentValue;
    case 'time':
      if (trimmed.isEmpty) return null;
      // The record and the picker both carry `HH:MM:SS`; the seconds are noise
      // the user never chose.
      final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(trimmed);
      if (m == null) return absentValue;
      final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
      if (h > 23 || min > 59) return absentValue;
      return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
    case 'date':
    case 'datetime':
      return trimmed.isEmpty ? null : trimmed;
    default:
      return trimmed;
  }
}

/// Sentinel meaning "do not send this key at all".
const Object absentValue = Object();
