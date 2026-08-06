import 'package:flutter/widgets.dart';

import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../domain/entities/crm_catalog.dart';

/// The org-configured option lists behind the Leads filters: the pipeline
/// stages (`/crm/lead-statuses/`) and the lead sources (`/crm/lead-sources/`).
///
/// Read-only here — the CRM Settings screens own their CRUD. Both lists are
/// small, rarely change, and are fetched whole (page size 100 covers any real
/// org; the stage list is capped far below that by the 5 status types).
///
/// Every fetch is **best-effort**: a failure yields an empty list rather than
/// throwing, because the caller's contract is "empty → fall back to the
/// built-in `StatusMeta$` vocabulary". A filter panel must never fail the list
/// behind it.
class CrmCatalogRemoteDataSource {
  const CrmCatalogRemoteDataSource(this._api);

  final ApiService _api;

  static const int _pageSize = 100;

  /// Pipeline stages, already banded by status type then within-type
  /// `position` server-side, so the returned order is the order to render.
  Future<List<CatalogOption>> fetchLeadStatuses() =>
      _fetch(ApiEndpoints.leadStatuses, 'lead_status_id', withType: true);

  /// Lead sources, active only — a deactivated source is not a filter the user
  /// should still be offered.
  Future<List<CatalogOption>> fetchLeadSources() => _fetch(
        ApiEndpoints.leadSources,
        'lead_source_id',
        query: {'is_active': true},
      );

  /// Products, for the Product/Service filter. Deliberately mapped to the same
  /// lightweight option shape rather than reusing the full `Product` entity:
  /// the filter needs a name to match on, not pricing, GST or revenue.
  Future<List<CatalogOption>> fetchProducts() =>
      _fetch(ApiEndpoints.products, 'product_id', nameKey: 'product_name');

  /// Org teams, for the Team filter. Needs the `view_team` permission — a role
  /// without it gets a 403, which surfaces here as an empty list (the section
  /// then falls back rather than the drawer failing).
  Future<List<CatalogOption>> fetchTeams() =>
      _fetch(ApiEndpoints.teams, 'team_id');

  Future<List<CatalogOption>> _fetch(
    String path,
    String idKey, {
    bool withType = false,
    String nameKey = 'name',
    Map<String, dynamic> query = const {},
  }) async {
    try {
      final body = await _api.get(path, query: {'page_size': _pageSize, ...query});
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      final out = <CatalogOption>[];
      for (final row in rows) {
        final option = mapCatalogRow(row, idKey, withType: withType, nameKey: nameKey);
        if (option != null) out.add(option);
      }
      return out;
    } on Object {
      return const [];
    }
  }

  // ── mapping (visible for tests) ──

  /// Maps one catalog row. Returns null when the row carries no usable name:
  /// the name is what list rows join on, so a nameless option could never
  /// match anything and would render as a blank chip.
  ///
  /// [nameKey] varies by catalog — statuses and sources use `name`, products
  /// use `product_name` (with `name` accepted as a fallback shape).
  static CatalogOption? mapCatalogRow(
    Map<String, dynamic> row,
    String idKey, {
    bool withType = false,
    String nameKey = 'name',
  }) {
    final name = (row[nameKey] ?? row['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final type = withType ? (row['status_type'] ?? '').toString().trim() : '';
    return CatalogOption(
      id: (row[idKey] ?? '').toString(),
      name: name,
      color: hexColor(row['color']),
      statusType: type.isEmpty ? null : type,
    );
  }
}

/// Parses a backend `#RRGGBB` colour. Returns null for an empty string (the
/// documented "no dot colour" value) or anything unparseable, so callers can
/// fall back to their own palette.
Color? hexColor(Object? v) {
  if (v is! String) return null;
  var hex = v.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(value);
}
