import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../domain/entities/crm_catalog.dart';
import '../../../domain/entities/package_composition.dart';
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
        // NOT `view_type=mobile`, deliberately. The org's mobile layout is
        // four fields, and the projection drops `product_type_id` /
        // `product_type_name` / `currency` / `hsn_code` / `unit` — verified
        // absent. The card's category chip is built from the product type, so
        // asking for the mobile payload would blank it. The card reads the
        // mobile *layout* for its extra columns; the payload stays the list
        // one until the org's mobile config carries what the card renders.
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

  /// `GET /crm/products/{id}/` — one catalog item.
  ///
  /// The detail screen used to pick its product out of the loaded list, so it
  /// could only show what that list happened to hold. Null on any failure,
  /// which sends the screen back to the list row.
  Future<Product?> fetchProduct(String id) async {
    if (id.isEmpty) return null;
    try {
      final body = await _api.get(ApiEndpoints.product(id));
      return body is Map<String, dynamic> ? productFromApi(body) : null;
    } on Object {
      return null;
    }
  }

  /// `GET /crm/product-types/` — the org's own categories (`products.md` §8).
  ///
  /// Carries the `product_type_id` as well as the label: the chips group by
  /// name, but the Add-product form writes `product_type`, which is the uuid.
  /// Empty on failure, which callers read as "no catalog, use the built-in
  /// list".
  Future<List<CatalogOption>> fetchProductTypes() async {
    try {
      final body =
          await _api.get(ApiEndpoints.productTypes, query: {'page_size': 100});
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      final out = <CatalogOption>[];
      for (final row in rows) {
        if (row['is_active'] == false) continue;
        final id = _str(row['product_type_id']);
        final name = _str(row['type_name']) ?? _str(row['name']);
        if (id == null || name == null) continue;
        if (out.any((o) => o.name == name)) continue;
        out.add(CatalogOption(id: id, name: name));
      }
      return out;
    } on Object {
      return const [];
    }
  }

  /// `PATCH /crm/products/{id}/` — partial update (`products.md` §4).
  ///
  /// [fields] is sent verbatim: unlike create, a caller here is naming exactly
  /// what it wants changed, and `{"is_active": false}` must survive the trip.
  Future<Product?> updateProduct(String id, Map<String, dynamic> fields) async {
    final res = await _api.patch(ApiEndpoints.product(id), body: fields);
    return res is Map<String, dynamic> ? productFromApi(res) : null;
  }

  /// `DELETE /crm/products/{id}/` — `204`, plus best-effort CDN image cleanup
  /// server-side (`products.md` §4).
  ///
  /// Not swallowed: the interesting case is the `400` raised when the product
  /// is a component of a package (the FK is `PROTECT`), and the caller has to
  /// show that reason rather than report a delete that did not happen.
  Future<void> deleteProduct(String id) => _api.delete(ApiEndpoints.product(id));

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
    // `item_type` is the serializer's own kind (`product` | `service` |
    // `package`); the rest are older shapes kept for other deployments.
    final itemType = (_str(row['item_type']) ?? '').toLowerCase();
    // The org's view config can drop `item_type` from the payload — it is
    // switched off on this org — and then nothing in a row said "package", so
    // every package landed in the Products tab and the Packages tab read 0.
    // A package is the only thing the serializer gives the six computed totals
    // to (`products.md` §7), so their presence identifies one when the explicit
    // field is unavailable.
    final hasPackageTotals = row.containsKey('computed_total_excl') ||
        row.containsKey('components_subtotal_excl');
    final isPackage = row['is_package'] == true ||
        itemType == 'package' ||
        (itemType.isEmpty && hasPackageTotals) ||
        '$cat ${_str(row['kind']) ?? ''}'.toLowerCase().contains('package');
    final price = parseAmount(row['price']);
    // `tax_rate` is the live field and arrives as a string ("18.00"). Reading
    // only `gst`/`tax_percent` meant every row fell through to the 18% default,
    // so a 0%-rated product was shown as 18% — with a gross price to match.
    final rate =
        _int(row['gst']) ?? _int(row['tax_percent']) ?? _rate(row['tax_rate']);
    // Absent ≠ zero ≠ 18. The org's Product view config can drop `tax_rate`
    // from the payload entirely, and a card that then prints "18% GST" is
    // stating a tax rate the server never sent.
    final gst = rate ?? 18;
    // `products.md` §2: the serializer's own names are `deals_count`,
    // `lifetime_revenue` and `avg_per_deal` — and all three are **stubs**
    // (`0`/`null`) until the quote↔product link lands, which is why no screen
    // may present them as real. Read the documented names so they light up on
    // their own when the backend fills them; the older guesses stay as
    // fallbacks for other deployments.
    final deals = _int(row['deals_count']) ??
        _int(row['deals']) ??
        _int(row['deal_count']) ??
        _int(row['usage_count']) ??
        0;
    final revenue = parseAmount(
        row['lifetime_revenue'] ?? row['revenue'] ?? row['total_revenue']);
    return Product(
      raw: row,
      id: id,
      name: _str(row['product_name']) ?? _str(row['name']) ?? '',
      kind: isPackage ? 'package' : 'product',
      cat: cat,
      code: _str(row['product_code']) ?? '',
      hsn: _str(row['hsn_sac']) ?? _str(row['hsn_code']) ?? _str(row['hsn']) ?? '',
      unit: _str(row['unit']) ?? _str(row['billing_unit']) ?? '',
      price: formatInr(price),
      // The number behind the display string, which `formatInr` abbreviates
      // beyond recovery.
      priceNum: price,
      gst: gst,
      gstKnown: rate != null,
      gstAmt: formatInr(price * gst / 100),
      gross: formatInr(price * (1 + gst / 100)),
      deals: deals,
      revenue: revenue > 0 ? formatInr(revenue) : '₹0',
      revNum: revenue.round(),
      avg: deals > 0 && revenue > 0 ? formatInr(revenue / deals) : '—',
      active: row['is_active'] != false,
      desc: _str(row['description']) ?? _str(row['desc']),
      composition: isPackage ? packageCompositionFromApi(row) : null,
      notes: const [],
    );
  } on Object {
    return null;
  }
}

/// A package's composition and totals (`products.md` §7), or null when the row
/// carries neither — which is every plain product.
///
/// `components`/`adjustments` are absent on this org (the view config withholds
/// them) while the six totals still arrive, so the two are read independently:
/// a package with totals and no line items is a real, renderable state.
PackageComposition? packageCompositionFromApi(Map<String, dynamic> row) {
  final hasTotals = row.containsKey('computed_total_excl') ||
      row.containsKey('components_subtotal_excl');
  final rawComponents = row['components'];
  final rawAdjustments = row['adjustments'];
  if (!hasTotals && rawComponents is! List && rawAdjustments is! List) return null;

  return PackageComposition(
    components: [
      if (rawComponents is List)
        for (final c in rawComponents)
          if (c is Map<String, dynamic>) _componentFromApi(c),
    ],
    adjustments: [
      if (rawAdjustments is List)
        for (final a in rawAdjustments)
          if (a is Map<String, dynamic>) _adjustmentFromApi(a),
    ],
    componentsExcl: parseAmount(row['components_subtotal_excl']),
    componentsIncl: parseAmount(row['components_subtotal_incl']),
    adjustmentsExcl: parseAmount(row['adjustments_total_excl']),
    adjustmentsIncl: parseAmount(row['adjustments_total_incl']),
    totalExcl: parseAmount(row['computed_total_excl']),
    totalIncl: parseAmount(row['computed_total_incl']),
  );
}

PackageComponent _componentFromApi(Map<String, dynamic> c) => PackageComponent(
      productId: _str(c['component_product']) ?? '',
      name: _str(c['product_name']) ?? '',
      code: _str(c['product_code']) ?? '',
      billingUnit: _str(c['billing_unit']) ?? '',
      quantity: _int(c['quantity']) ?? 1,
      unitPrice: parseAmount(c['unit_price']),
      lineExcl: parseAmount(c['line_excl']),
      lineIncl: parseAmount(c['line_incl']),
    );

PackageAdjustment _adjustmentFromApi(Map<String, dynamic> a) {
  // `amount` is stored positive; the sign lives in `sign`, derived from the
  // type (discounts are -1). Older rows may omit it, so the type decides.
  final type = _str(a['adjustment_type']) ?? '';
  final sign = _int(a['sign']) ?? (type == 'bundle_discount' ? -1 : 1);
  return PackageAdjustment(
    type: type,
    label: _str(a['label']) ?? '',
    amount: parseAmount(a['amount']),
    sign: sign < 0 ? -1 : 1,
    amountIncl: parseAmount(a['amount_incl']),
  );
}

/// Raw category name. Unknown categories are safe downstream (the list only
/// groups on known keys; colour/icon maps fall back to a neutral default), so
/// no remapping to a known bucket is done here.
///
/// `product_type` is a **uuid** on the live serializer and `product_type_name`
/// carries the name, so reading the former first put a uuid in the category
/// chip, the detail row and the grouping key.
String _category(Map<String, dynamic> row) {
  final name = _str(row['product_type_name']);
  if (name != null) return name;
  final typeRaw = row['product_type'] ?? row['category'] ?? row['type'];
  if (typeRaw is Map) return _str(typeRaw['name']) ?? _str(typeRaw['type_name']) ?? '';
  final s = _str(typeRaw);
  // A bare uuid is the id, not a name — nothing to show.
  return s == null || _uuidRe.hasMatch(s) ? '' : s;
}

final RegExp _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// A percentage that may arrive as a number or as a decimal string ("18.00").
int? _rate(Object? v) {
  if (v is num) return v.round();
  if (v is String) {
    final parsed = double.tryParse(v.trim());
    if (parsed != null) return parsed.round();
  }
  return null;
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

int? _int(Object? v) => v is num ? v.toInt() : null;
