import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../domain/entities/saved_filter.dart';

/// CRUD over `/crm/saved-filters/` — the per-user, per-module filter presets
/// behind the saved-view chips.
///
/// Unlike the catalog reads, the writes here deliberately **do not** swallow
/// errors: the API returns user-safe 400 messages (duplicate name, empty
/// definition, unknown filter key, 5-per-module limit) that belong in front of
/// the user, not in a silent no-op.
class SavedFiltersRemoteDataSource {
  const SavedFiltersRemoteDataSource(this._api);

  final ApiService _api;

  /// `GET /crm/saved-filters/?module=<module>` — the caller's own presets,
  /// ordered by `(module, order, created_at)`. Always a paginated envelope.
  Future<List<SavedFilter>> fetch(String module) async {
    final body = await _api.get(ApiEndpoints.savedFilters, query: {'module': module});
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    final out = <SavedFilter>[];
    for (final row in rows) {
      final f = mapSavedFilter(row);
      if (f != null) out.add(f);
    }
    return out;
  }

  /// `POST /crm/saved-filters/` — returns the created object, unwrapped.
  Future<SavedFilter?> create({
    required String module,
    required String name,
    required Map<String, dynamic> definition,
    int order = 0,
  }) async {
    final body = await _api.post(ApiEndpoints.savedFilters, body: {
      'module': module,
      'name': name,
      'filter_definition': definition,
      'order': order,
    });
    return body is Map<String, dynamic> ? mapSavedFilter(body) : null;
  }

  /// `PATCH /crm/saved-filters/{id}/` — rename and/or redefine in place. The
  /// 5-per-module limit does not apply to an edit, so this always succeeds even
  /// when the module is full.
  Future<SavedFilter?> update(
    String id, {
    String? name,
    Map<String, dynamic>? definition,
  }) async {
    final body = await _api.patch(ApiEndpoints.savedFilter(id), body: {
      if (name != null) 'name': name,
      if (definition != null) 'filter_definition': definition,
    });
    return body is Map<String, dynamic> ? mapSavedFilter(body) : null;
  }

  /// `DELETE /crm/saved-filters/{id}/` → 204.
  Future<void> delete(String id) => _api.delete(ApiEndpoints.savedFilter(id));

  // ── mapping (visible for tests) ──

  /// Maps one row. Returns null without an id or a name — the two fields the
  /// response contract marks hard-required.
  static SavedFilter? mapSavedFilter(Map<String, dynamic> row) {
    final id = (row['saved_filter_id'] ?? '').toString();
    final name = (row['name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty) return null;
    final def = row['filter_definition'];
    return SavedFilter(
      id: id,
      name: name,
      definition: def is Map ? Map<String, dynamic>.from(def) : const {},
      isValid: row['is_valid'] != false,
      invalidReason: row['invalid_reason']?.toString(),
      order: (row['order'] as num?)?.toInt() ?? 0,
    );
  }
}
