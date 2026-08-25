import '../domain/entities/view_schema.dart';

/// Rendering a schema-configured column that the app has no typed field for.
///
/// Shared by every CRM card. The typed entity covers the fixed frame; this is
/// what makes the rest open-ended — a column an admin adds tomorrow renders
/// with whatever the backend returns for it, without a code change.

/// The extra columns to render as chips: everything the org made visible that
/// the card's fixed frame does not already show, in the org's order.
///
/// [frame] names the columns the card draws itself; [text] resolves a column
/// against the module's own entity, falling back to its raw row.
List<({String label, String value})> schemaExtraColumns(
  ViewSchema schema,
  Set<String> frame,
  String? Function(ViewColumn column) text,
) {
  final out = <({String label, String value})>[];
  for (final column in schema.columns) {
    if (frame.contains(column.name)) continue;
    final value = text(column);
    if (value == null || value.isEmpty) continue;
    out.add((label: column.label, value: value));
  }
  return out;
}

/// Keys that are never worth a chip: identifiers, the custom-field container,
/// and bookkeeping the user did not ask to see.
const Set<String> kNeverChipped = {
  'id',
  'custom_fields',
  'organization',
  'created_by',
  'modified_by',
  'updated_by',
  'owner',
};

/// True for a key that is plainly an identifier rather than information.
bool _isIdKey(String key) =>
    key.endsWith('_id') || key.endsWith('_ids') || key == 'uuid';

/// `product_code` → `Product Code`. Used only for a row key the schema does not
/// describe, so there is no server-provided label to prefer.
String humanizeKey(String key) => key
    .split(RegExp(r'[_\s]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w.length == 1 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Every renderable field on a row, whether or not the schema mentions it.
///
/// [schemaExtraColumns] answers "what did the org configure"; this answers
/// "what actually arrived". The card wants the second: a payload gains and
/// loses fields as the backend changes, and a field nobody has heard of yet
/// should still show up with its value rather than waiting for a release.
///
/// Order: the org's configured columns first — they carry real labels and a
/// deliberate order — then anything else on the row, alphabetically, labelled
/// from its key. Identifiers and containers are skipped; an empty value is
/// skipped rather than drawn blank.
List<({String label, String value})> dynamicRowColumns({
  required Map<String, dynamic> raw,
  required ViewSchema schema,
  required Set<String> frame,
  required String? Function(ViewColumn column) text,
}) {
  final out = <({String label, String value})>[];
  final seen = <String>{...frame};

  for (final column in schema.columns) {
    if (!seen.add(column.name)) continue;
    final value = text(column);
    if (value == null || value.isEmpty) continue;
    out.add((label: column.label, value: value));
  }

  final rest = raw.keys.where((k) => !seen.contains(k)).toList()..sort();
  for (final key in rest) {
    if (kNeverChipped.contains(key) || _isIdKey(key)) continue;
    final value = formatRawValue(raw[key]);
    if (value == null || value.isEmpty) continue;
    out.add((label: humanizeKey(key), value: value));
  }
  return out;
}

/// Reads [column] straight off a raw API row, by name.
String? rawColumnText(Map<String, dynamic> raw, ViewColumn column) =>
    formatRawValue(raw[column.customKey] ?? raw[column.name]);

/// A raw JSON value as one line of card text, or null when there is nothing
/// worth showing.
///
/// Deliberately shape-driven rather than name-driven — it has to cope with a
/// field this code has never heard of:
/// * a nested object shows its own display name (`name` / `full_name` / …),
///   because a bare uuid is not information;
/// * a list shows its members' names, or a count when they are not nameable;
/// * a bool reads Yes/No rather than `true`;
/// * an ISO timestamp is shortened to its date.
String? formatRawValue(Object? value) {
  if (value == null) return null;

  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) return '$value';

  if (value is Map) {
    for (final key in const ['name', 'full_name', 'title', 'label', 'display_name']) {
      final v = value[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null; // an object with no human-readable field: a bare id, skip it
  }

  if (value is List) {
    if (value.isEmpty) return null;
    final names = <String>[
      for (final item in value)
        if (formatRawValue(item) case final text?) text,
    ];
    if (names.isNotEmpty) return names.join(', ');
    return '${value.length}';
  }

  final text = value.toString().trim();
  if (text.isEmpty) return null;
  // `2026-08-14T04:20:54.244476Z` reads as a date on a card, not a timestamp.
  final parsed = DateTime.tryParse(text);
  if (parsed != null && text.contains('-') && text.length >= 10) {
    return text.substring(0, 10);
  }
  return text;
}
