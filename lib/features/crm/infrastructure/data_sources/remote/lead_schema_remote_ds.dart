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

  /// The layout for the lead detail page.
  ///
  /// No fallback to another view type: `detail` is the only layout that
  /// describes this screen, and it is also what the **record** endpoint trims
  /// itself to (`GET /crm/leads/{id}/` resolves `retrieve` → `detail`). Layout
  /// and payload therefore agree here, unlike the list.
  ///
  /// Fetching this also has a side effect the server documents: an org's detail
  /// config seeds lazily on the first `schema/?view_type=detail` call, and until
  /// it exists the record endpoint returns the whole untrimmed lead. Asking for
  /// the layout is what makes the trim start applying.
  Future<LeadListSchema> fetchDetailSchema() => _fetch('detail');

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
  //
  // The parsing itself lives on [ViewSchema], shared with the other modules
  // that drive off the same Org View Settings shape. These stay as the Leads
  // entry points.

  /// Maps a `/schema/` response.
  static LeadListSchema mapSchema(Object? body) => ViewSchema.fromResponse(body);

  /// Maps one column, or null when it is hidden or unusable.
  static LeadColumn? mapColumn(Object? row) => ViewColumn.fromJson(row);
}
