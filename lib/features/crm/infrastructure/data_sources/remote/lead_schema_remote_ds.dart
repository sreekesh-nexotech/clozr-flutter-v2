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

  /// The layout for the mobile list card — `mobile`, and only `mobile`.
  ///
  /// `mobile` is the view type meant for this screen, so it is the one the card
  /// obeys. There is deliberately **no fallback to `list`**: the two layouts are
  /// configured independently and an org that trims its mobile view has said
  /// what it wants on a phone. Borrowing the table layout would quietly show
  /// columns that were removed on purpose.
  ///
  /// An org with no `mobile` rows resolves to [LeadListSchema.empty], whose
  /// contract everywhere is "no opinion — render the built-in layout". That is
  /// the honest answer for an unconfigured org, and it is what the card already
  /// does while the fetch is in flight.
  ///
  /// Note the layout is `mobile` but the **payload** is trimmed to the org's
  /// `list` config: the data endpoints resolve their view type from the request
  /// action, not a query param. A column visible on the card but hidden on the
  /// list therefore arrives with no value — which renders as absent, since the
  /// card skips empty values.
  Future<LeadListSchema> fetchListSchema() => _fetch('mobile');

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
