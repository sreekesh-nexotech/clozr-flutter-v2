import '../../../../../core/network/api_service.dart';
import '../../../domain/entities/view_schema.dart';

/// The org's configured layout for one CRM module: `GET /<module>/schema/`.
///
/// Generic because the contract is: every module exposes `?view_type=list |
/// detail | mobile` at `<collection>/schema/`, and the response shape is the
/// same one [ViewSchema.fromResponse] already parses. Leads, Tasks and
/// Follow-ups each grew their own class before that was clear; Customers,
/// Quotes and Payments share this one.
class ModuleSchemaRemoteDataSource {
  const ModuleSchemaRemoteDataSource(this._api, {required this.schemaPath});

  final ApiService _api;

  /// e.g. `/crm/customers/schema/`.
  final String schemaPath;

  /// The mobile list-row card layout.
  ///
  /// `mobile` is the view type meant for a phone list, and the view-settings
  /// engine treats it as standalone (no `both` merge). Orgs seeded before that
  /// view type existed have no `mobile` rows, so `list` is the fallback — the
  /// same two-step Tasks uses.
  Future<ViewSchema> fetchListSchema() async {
    final mobile = await _fetch('mobile');
    return mobile.isNotEmpty ? mobile : _fetch('list');
  }

  /// The mobile card layout — `mobile`, and only `mobile`.
  ///
  /// For a module whose **data** request also asks for `?view_type=mobile`: the
  /// layout and the payload then describe the same field set, and falling back
  /// to `list` would pair a list layout with a mobile payload — slots the rows
  /// no longer carry.
  ///
  /// An org with no mobile rows resolves to [ViewSchema.empty], whose contract
  /// is "no opinion — render the built-in layout".
  Future<ViewSchema> fetchMobileSchema() => _fetch('mobile');

  /// The detail-panel layout. This is also what the record endpoint trims itself
  /// to, so layout and payload agree: a visible column with no value means the
  /// record genuinely has none.
  Future<ViewSchema> fetchDetailSchema() => _fetch('detail');

  /// Best-effort by design. Any failure — a 403, an org with no config, a module
  /// the backend has not seeded — yields the empty schema, which every consumer
  /// reads as "no opinion, render the built-in layout". A screen must never be
  /// blank because its layout call failed.
  Future<ViewSchema> _fetch(String viewType) async {
    try {
      final body = await _api.get(schemaPath, query: {'view_type': viewType});
      return ViewSchema.fromResponse(body);
    } on Object {
      return ViewSchema.empty;
    }
  }

  /// One record, **unmapped**.
  ///
  /// The schema-driven panel renders whichever columns the org configured, so it
  /// needs values by field name — which the typed entity cannot give, since it
  /// only carries the fields the built-in layout happened to need.
  Future<Map<String, dynamic>?> fetchRow(String path) async {
    try {
      final body = await _api.get(path);
      return body is Map<String, dynamic> ? body : null;
    } on Object {
      return null;
    }
  }
}
