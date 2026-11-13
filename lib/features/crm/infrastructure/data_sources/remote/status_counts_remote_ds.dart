import '../../../../../core/network/api_service.dart';
import '../../../../../core/status_groups/status_groups.dart';

/// The list headers' counts for leads and CRM tasks / follow-ups —
/// `GET /crm/leads/status-counts/` and `GET /crm/tasks/status-counts/`
/// (`?is_followup=true` for follow-ups).
///
/// The server applies the list's own scope (record permissions, drawer
/// filters, saved filter, search, archived mode) minus the status facets, so
/// picking a chip never zeroes the others.
class StatusCountsRemoteDataSource {
  const StatusCountsRemoteDataSource(this._api);

  final ApiService _api;

  /// The "Other / no status" key — the same chip key the lead and task lists
  /// use for it.
  static const otherKey = '__other__';

  /// Returns `'all'` → total, [otherKey] → no status or an inactive one,
  /// [StatusGroups.countKey] → each group's total, and each active status's
  /// lower-cased name (`CatalogOption.key`, what the chips join on) → count.
  ///
  /// Best-effort: a failure yields an empty map, which the header reads as
  /// "count the loaded rows instead".
  Future<Map<String, int>> fetch(
      String endpoint, Map<String, dynamic> filters) async {
    try {
      final body = await _api.get(endpoint,
          query: {...filters}..removeWhere(_isDropped), quiet: true);
      if (body is! Map) return const {};
      final out = <String, int>{
        'all': _int(body['total']),
        otherKey: _int(body['other'])
      };
      for (final row in (body['statuses'] as List? ?? const [])) {
        if (row is! Map) continue;
        final key = '${row['name'] ?? ''}'.toLowerCase().trim();
        if (key.isNotEmpty) out[key] = (out[key] ?? 0) + _int(row['count']);
      }
      StatusGroups.readGroupCounts(body, out);
      return out;
    } on Object {
      return const {};
    }
  }

  /// Paging and the list-only card trim mean nothing to an aggregate, and the
  /// status facets are stripped server-side anyway — dropped so one cached
  /// answer serves every chip.
  static bool _isDropped(String k, Object? _) =>
      k == 'page' ||
      k == 'page_size' ||
      k == 'view_type' ||
      k == 'status' ||
      k == 'status_id' ||
      k == 'status_type' ||
      k.startsWith('status__') ||
      k.startsWith('status_name');

  static int _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
}
