import 'package:equatable/equatable.dart';

/// One column of an org-configured layout, as any module's
/// `GET /<module>/schema/?view_type=…` reports it.
///
/// The Org View Settings engine serves the same shape for every module, so the
/// same parser drives Leads and Quotes (and whatever comes next).
///
/// [name] is the payload key the column reads from — a built-in field
/// (`lead_value`) or a custom field (`custom_fields.budget`). [label] is the
/// org's own header for it: an admin's `label_override` already applied
/// server-side, so it is what the user should see.
class ViewColumn extends Equatable {
  const ViewColumn({
    required this.name,
    required this.label,
    required this.order,
    this.type = '',
    this.isCustom = false,
    this.isFixed = false,
    this.inFields = false,
    this.relatedModel = '',
  });

  final String name;
  final String label;

  /// Server-assigned sort position. Gaps are expected; only the relative order
  /// is meaningful.
  final int order;

  /// Field type (`text`, `number`, `date`, `boolean`, `dropdown`, …), used to
  /// format the value. Empty for columns the schema sends without `field_info`
  /// (system-managed ones like `lead_score` and `created_at`).
  final String type;

  /// True for `custom_fields.<slug>` columns — their value lives in the row's
  /// `custom_fields` object rather than a top-level key.
  final bool isCustom;

  /// A protected column the org cannot hide.
  final bool isFixed;

  /// Whether the column is a real serializer field (`in_fields`) rather than a
  /// display-only one.
  ///
  /// This is what separates a column you can *edit* from one you can only
  /// *read*: `lead_value` is visible and labelled "Value / Need", but arrives
  /// with `in_fields: false` and no `field_info` — the API accepts a write to
  /// it, returns `200`, and stores nothing.
  final bool inFields;

  /// For `foreignkey` / `manytomany` columns, the model the value points at
  /// (`LeadSource`, `LeadStatus`, `User`, `Territory`, …). Empty otherwise.
  final String relatedModel;

  /// Maps one column, or null when it is hidden or unusable. `visible` is
  /// treated as opt-in: a column that does not say it is visible is not shown.
  static ViewColumn? fromJson(Object? row) {
    if (row is! Map) return null;
    if (row['visible'] != true) return null;

    final name = (row['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    final info = row['field_info'];
    final isCustom = (info is Map && info['is_custom'] == true) ||
        name.startsWith('custom_fields.');
    final label = (row['label'] ?? '').toString().trim();

    return ViewColumn(
      name: name,
      // A column with no label is still renderable — fall back to its key
      // rather than dropping the field.
      label: label.isNotEmpty ? label : name,
      order: (row['order'] as num?)?.toInt() ?? 0,
      type: info is Map ? (info['type'] ?? '').toString() : '',
      isCustom: isCustom,
      // Detail views send no `is_fixed` at all — only `is_protected`.
      isFixed: row['is_fixed'] == true || row['is_protected'] == true,
      // `field_info` is only present for serializer fields, so its presence is
      // the same signal as the flag; either one is enough.
      inFields: row['in_fields'] == true || info is Map,
      relatedModel:
          info is Map ? (info['related_model'] ?? '').toString() : '',
    );
  }

  /// Whether this column can be rendered as an input on a form.
  ///
  /// Custom fields are excluded for now: they live under `custom_fields.<slug>`
  /// and need their own write shape, which no screen builds yet.
  bool get isEditable => inFields && !isCustom && type.isNotEmpty;

  /// Whether the value is chosen from a catalog rather than typed.
  bool get isChoice => type == 'foreignkey' || type == 'manytomany';

  /// Whether the column holds several values.
  bool get isMulti => type == 'manytomany';

  /// The `custom_fields` key this column reads, for custom columns.
  String get customKey =>
      isCustom ? name.substring(name.indexOf('.') + 1) : name;

  @override
  List<Object?> get props =>
      [name, label, order, type, isCustom, isFixed, inFields, relatedModel];
}

/// The org's Leads list layout: which columns to render, in which order, under
/// which labels.
///
/// An **empty** schema is the documented "no opinion" value — mock mode, a
/// fetch that failed, or an org with no config. Every caller must fall back to
/// the built-in layout when [isEmpty], so the screen renders exactly as it did
/// before this became configurable.
class ViewSchema extends Equatable {
  const ViewSchema({this.columns = const [], this.hasOrgConfig = false});

  static const ViewSchema empty = ViewSchema();

  /// Visible columns only, in the org's order.
  final List<ViewColumn> columns;

  /// Whether the org has customised its layout. False means the server served
  /// seeded defaults, which is still a usable layout.
  final bool hasOrgConfig;

  bool get isEmpty => columns.isEmpty;
  bool get isNotEmpty => columns.isNotEmpty;

  /// Whether [name] is a visible column. An empty schema answers **true** for
  /// everything: with no layout to honour, nothing should be hidden.
  bool shows(String name) =>
      isEmpty || columns.any((c) => c.name == name);

  /// Whether any of [names] is visible — for card slots fed by more than one
  /// field (the sub-title reads `products`, else `lead_source`).
  bool showsAny(Iterable<String> names) =>
      isEmpty || names.any(shows);

  /// Parses a `/schema/` response. Hidden columns are dropped here — a settings
  /// panel needs them to render toggles, a screen never does.
  static ViewSchema fromResponse(Object? body) {
    if (body is! Map<String, dynamic>) return ViewSchema.empty;
    final all = body['all_fields'];
    final rows = all is Map ? all['columns'] : null;
    if (rows is! List) return ViewSchema.empty;

    final columns = <ViewColumn>[];
    for (final row in rows) {
      final column = ViewColumn.fromJson(row);
      if (column != null) columns.add(column);
    }
    columns.sort((a, b) => a.order.compareTo(b.order));

    return ViewSchema(
      columns: columns,
      hasOrgConfig: body['has_org_config'] == true,
    );
  }

  /// The columns a form can render as inputs, in the org's order.
  ///
  /// Narrower than [columns]: a layout mixes editable fields with display-only
  /// ones (`lead_value`, `lead_score`, `created_at`), and putting a box around
  /// a display-only field produces a form that accepts input the API discards.
  List<ViewColumn> get editableColumns =>
      [for (final c in columns) if (c.isEditable) c];

  ViewColumn? column(String name) {
    for (final c in columns) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// The org's label for [name], or [fallback] when the column is absent.
  String labelOf(String name, String fallback) =>
      column(name)?.label ?? fallback;

  @override
  List<Object?> get props => [columns, hasOrgConfig];
}
