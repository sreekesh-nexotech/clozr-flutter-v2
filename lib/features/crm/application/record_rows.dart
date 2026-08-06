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
typedef RecordRow = ({String name, String label, String value});

/// The rows to render: every visible column the caller has not already placed
/// in the page's own chrome, in the org's order and under the org's labels.
///
/// A column the record has **no value** for still renders, as `—`: layout and
/// payload come from the same detail config, so an empty value means the record
/// genuinely has none — which on a detail page is information, not noise. A
/// column the row does not carry **at all** is dropped, since that means the
/// payload and the layout disagree and there is nothing truthful to show.
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
    if (identical(raw, _absent)) continue;
    out.add((
      name: column.name,
      label: column.label,
      value: recordValueText(raw, column.type),
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
