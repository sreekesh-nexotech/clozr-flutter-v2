import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../domain/entities/product.dart';

/// Raw catalog endpoints (`/crm/products/`). HTTP + JSON→entity mapping only —
/// caching lives in the API repository.
class ProductsRemoteDataSource {
  const ProductsRemoteDataSource(this._api);

  final ApiService _api;

  /// Raw `/crm/products/` rows, following `next` up to 3 pages. The repository
  /// caches these and maps them via [productsFromApiRows].
  Future<List<Map<String, dynamic>>> fetchProductRows() async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 50) {
      final body = await _api.get(ApiEndpoints.products, query: {
        'page': page,
        'page_size': ApiConfig.defaultPageSize,
      });
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      out.addAll(paged.results);
      if (!paged.hasMore) break;
      page++;
    }
    return out;
  }

  /// `POST /crm/products/` — sends only non-empty fields; maps the created row
  /// back to a [Product] (null when the response shape is unexpected).
  Future<Product?> createProduct(Map<String, dynamic> fields) async {
    final body = <String, dynamic>{};
    for (final entry in fields.entries) {
      final v = entry.value;
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      body[entry.key] = v;
    }
    final res = await _api.post(ApiEndpoints.products, body: body);
    return res is Map<String, dynamic> ? productFromApi(res) : null;
  }
}

// ── JSON → entity mapping (public so the repository and tests reuse it) ──

/// Maps a list of raw rows, skipping malformed entries.
List<Product> productsFromApiRows(List<dynamic> rows) {
  final out = <Product>[];
  for (final r in rows) {
    if (r is Map<String, dynamic>) {
      final p = productFromApi(r);
      if (p != null) out.add(p);
    }
  }
  return out;
}

/// Maps one `/crm/products/` row → [Product]. Returns null when the row is
/// unusable (no id) — a malformed row is skipped, never fatal. Field naming
/// varies across deployments (`product_type` name/object vs `category`), so
/// every read is defensive with documented defaults.
Product? productFromApi(Map<String, dynamic> row) {
  final id = _str(row['product_id']);
  if (id == null) return null;
  try {
    final cat = _category(row);
    final isPackage = row['is_package'] == true ||
        '$cat ${_str(row['kind']) ?? ''} ${_str(row['product_type']) ?? ''}'
            .toLowerCase()
            .contains('package');
    final price = parseAmount(row['price']);
    final gst = _int(row['gst']) ?? _int(row['tax_percent']) ?? 18;
    final deals = _int(row['deals']) ?? _int(row['deal_count']) ?? _int(row['usage_count']) ?? 0;
    final revenue = parseAmount(row['revenue'] ?? row['total_revenue']);
    return Product(
      id: id,
      name: _str(row['product_name']) ?? _str(row['name']) ?? '',
      kind: isPackage ? 'package' : 'product',
      cat: cat,
      hsn: _str(row['hsn_code']) ?? _str(row['hsn']) ?? '',
      unit: _str(row['unit']) ?? _str(row['billing_unit']) ?? '',
      price: formatInr(price),
      gst: gst,
      gstAmt: formatInr(price * gst / 100),
      gross: formatInr(price * (1 + gst / 100)),
      deals: deals,
      revenue: revenue > 0 ? formatInr(revenue) : '₹0',
      revNum: revenue.round(),
      avg: deals > 0 && revenue > 0 ? formatInr(revenue / deals) : '—',
      active: row['is_active'] != false,
      desc: _str(row['description']) ?? _str(row['desc']),
      notes: const [],
    );
  } on Object {
    return null;
  }
}

/// Raw category name. Unknown categories are safe downstream (the list only
/// groups on known keys; colour/icon maps fall back to a neutral default), so
/// no remapping to a known bucket is done here.
String _category(Map<String, dynamic> row) {
  final typeRaw = row['product_type'] ?? row['category'] ?? row['type'];
  if (typeRaw is Map) return _str(typeRaw['name']) ?? '';
  return _str(typeRaw) ?? '';
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

int? _int(Object? v) => v is num ? v.toInt() : null;
