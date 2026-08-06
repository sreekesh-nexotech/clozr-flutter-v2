import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../domain/entities/lead_schema.dart';

/// The org's Leads layout: `GET /crm/leads/schema/?view_type=…`.
///
/// Best-effort like the other catalogs — any failure yields
/// [LeadListSchema.empty], whose contract is "render the built-in layout". A
/// layout lookup must never fail the list behind it.
class LeadSchemaRemoteDataSource {
  const LeadSchemaRemoteDataSource(this._api);

  final ApiService _api;

  /// The layout for the mobile list card, falling back to the table layout.
  ///
  /// `mobile` is the view type meant for this screen (the server seeds it as a
  /// compact subset: name, company, status, value, assignees). Orgs seeded
  /// before that view type existed have no `mobile` rows, and the server's own
  /// fallback only covers the data endpoints — so ask for `list` here when
  /// `mobile` comes back with nothing to render.
  ///
  /// Note the layout is `mobile` but the **payload** is trimmed to the org's
  /// `list` config: the data endpoints resolve their view type from the request
  /// action, not a query param. A column visible on the card but hidden on the
  /// list therefore arrives with no value — which renders as absent, since the
  /// card skips empty values.
  Future<LeadListSchema> fetchListSchema() async {
    final mobile = await _fetch('mobile');
    return mobile.isNotEmpty ? mobile : _fetch('list');
  }

  Future<LeadListSchema> _fetch(String viewType) async {
    try {
      final body = await _api.get(
        ApiEndpoints.leadSchema,
        query: {'view_type': viewType},
      );
      return mapSchema(body);
    } on Object {
      return LeadListSchema.empty;
    }
  }

  // ── mapping (visible for tests) ──

  /// Maps a `/schema/` response. Hidden columns are dropped here — the settings
  /// panel needs them to render toggles, a list card never does.
  static LeadListSchema mapSchema(Object? body) {
    if (body is! Map<String, dynamic>) return LeadListSchema.empty;
    final all = body['all_fields'];
    final rows = all is Map ? all['columns'] : null;
    if (rows is! List) return LeadListSchema.empty;

    final columns = <LeadColumn>[];
    for (final row in rows) {
      final column = mapColumn(row);
      if (column != null) columns.add(column);
    }
    columns.sort((a, b) => a.order.compareTo(b.order));

    return LeadListSchema(
      columns: columns,
      hasOrgConfig: body['has_org_config'] == true,
    );
  }

  /// Maps one column, or null when it is hidden or unusable. `visible` is
  /// treated as opt-in: a column that does not say it is visible is not shown.
  static LeadColumn? mapColumn(Object? row) {
    if (row is! Map) return null;
    if (row['visible'] != true) return null;

    final name = (row['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    final info = row['field_info'];
    final isCustom =
        (info is Map && info['is_custom'] == true) || name.startsWith('custom_fields.');

    final label = (row['label'] ?? '').toString().trim();

    return LeadColumn(
      name: name,
      // A column with no label is still renderable — fall back to its key
      // rather than dropping the field.
      label: label.isNotEmpty ? label : name,
      order: (row['order'] as num?)?.toInt() ?? 0,
      type: info is Map ? (info['type'] ?? '').toString() : '',
      isCustom: isCustom,
      isFixed: row['is_fixed'] == true || row['is_protected'] == true,
    );
  }
}
