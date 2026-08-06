import 'package:equatable/equatable.dart';

/// One column of the org's configured Leads layout, as
/// `GET /crm/leads/schema/` reports it.
///
/// [name] is the payload key the column reads from — a built-in field
/// (`lead_value`) or a custom field (`custom_fields.budget`). [label] is the
/// org's own header for it: an admin's `label_override` already applied
/// server-side, so it is what the user should see.
class LeadColumn extends Equatable {
  const LeadColumn({
    required this.name,
    required this.label,
    required this.order,
    this.type = '',
    this.isCustom = false,
    this.isFixed = false,
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

  /// The `custom_fields` key this column reads, for custom columns.
  String get customKey =>
      isCustom ? name.substring(name.indexOf('.') + 1) : name;

  @override
  List<Object?> get props => [name, label, order, type, isCustom, isFixed];
}

/// The org's Leads list layout: which columns to render, in which order, under
/// which labels.
///
/// An **empty** schema is the documented "no opinion" value — mock mode, a
/// fetch that failed, or an org with no config. Every caller must fall back to
/// the built-in layout when [isEmpty], so the screen renders exactly as it did
/// before this became configurable.
class LeadListSchema extends Equatable {
  const LeadListSchema({this.columns = const [], this.hasOrgConfig = false});

  static const LeadListSchema empty = LeadListSchema();

  /// Visible columns only, in the org's order.
  final List<LeadColumn> columns;

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

  LeadColumn? column(String name) {
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
