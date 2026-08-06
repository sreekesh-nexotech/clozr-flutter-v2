import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../domain/entities/view_schema.dart';

/// The org's Follow-ups layout: `GET /crm/tasks/schema/?view_type=…`.
///
/// Follow-ups share the Task resource (`is_followup=true`), and so does the
/// schema route — but the two have **separate** field configs. Passing
/// `is_followup=true` is what selects the Follow-up one; without it the
/// response comes back as `model: Task` and describes the Tasks screen instead.
///
/// Best-effort like the other catalogs: any failure yields [ViewSchema.empty],
/// whose contract is "render the built-in layout". A layout lookup must never
/// fail the list behind it.
class FollowupSchemaRemoteDataSource {
  const FollowupSchemaRemoteDataSource(this._api);

  final ApiService _api;

  /// The layout for the mobile list card, falling back to the table layout.
  ///
  /// `mobile` is the view type meant for this screen — the server seeds it as a
  /// compact subset (title, status, priority, due date, assigned to). An org
  /// seeded before that view type existed has no `mobile` rows, so fall back to
  /// `list` when nothing comes back.
  ///
  /// Note the layout is `mobile` while the **payload** is trimmed to the org's
  /// `list` config: the data endpoint resolves its view type from the action,
  /// not from a query param. A column visible on the card but hidden on the
  /// list therefore arrives with no value — which renders as absent, since the
  /// card skips empty values.
  Future<ViewSchema> fetchCardSchema() async {
    final mobile = await _fetch('mobile');
    return mobile.isNotEmpty ? mobile : _fetch('list');
  }

  Future<ViewSchema> _fetch(String viewType) async {
    try {
      final body = await _api.get(ApiEndpoints.crmTaskSchema, query: {
        'view_type': viewType,
        'is_followup': true,
      });
      return ViewSchema.fromResponse(body);
    } on Object {
      return ViewSchema.empty;
    }
  }
}
