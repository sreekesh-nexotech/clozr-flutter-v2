import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../domain/entities/billing.dart';

/// The three billing collections the app can read.
///
/// No `billing.md` exists, so these mappings were built from the live payloads
/// and are deliberately tolerant: an unknown status word passes through, a
/// missing money field reads zero, and a null storage cap means "unlimited"
/// rather than "zero".
class BillingRemoteDataSource {
  const BillingRemoteDataSource(this._api);

  final ApiService _api;

  static const String _storage = '/billing/storage/';
  static const String _plans = '/billing/plans/';

  /// `GET /billing/invoices/` — the billing-history list, newest first.
  Future<List<BillingInvoice>> fetchInvoices() async {
    final body = await _api.get(ApiEndpoints.billingInvoices, query: {
      'page_size': 100,
    });
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    final out = [for (final row in rows) invoiceFromJson(row)];
    // The API returns them oldest-first; a billing history reads newest-first.
    out.sort((a, b) {
      final x = a.periodEnd ?? a.dueDate;
      final y = b.periodEnd ?? b.dueDate;
      if (x == null || y == null) return 0;
      return y.compareTo(x);
    });
    return out;
  }

  /// `GET /billing/storage/` — org file usage.
  Future<StorageUsage> fetchStorage() async {
    final body = await _api.get(_storage);
    return storageFromJson(body);
  }

  /// `GET /billing/plans/` — the plans on offer, cheapest first.
  Future<List<BillingPlan>> fetchPlans() async {
    final body = await _api.get(_plans, query: {'page_size': 50});
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    final out = [
      for (final row in rows)
        if (row['is_active'] != false) planFromJson(row),
    ];
    out.sort((a, b) => a.monthlyPerUser.compareTo(b.monthlyPerUser));
    return out;
  }

  // ── mapping ──

  static BillingInvoice invoiceFromJson(Map<String, dynamic> row) {
    final items = row['line_items'];
    return BillingInvoice(
      id: _str(row['invoice_id']) ?? '',
      number: _str(row['invoice_number']) ?? '',
      status: _str(row['status']) ?? '',
      total: parseAmount(row['total_amount']),
      amountDue: parseAmount(row['amount_due']),
      periodStart: parseApiDate(row['period_start']),
      periodEnd: parseApiDate(row['period_end']),
      dueDate: parseApiDate(row['due_date']),
      paidAt: parseApiDate(row['paid_at']),
      lineItems: [
        if (items is List)
          for (final item in items)
            if (item is Map<String, dynamic>) _lineFromJson(item),
      ],
    );
  }

  static BillingLineItem _lineFromJson(Map<String, dynamic> row) =>
      BillingLineItem(
        description: _str(row['description']) ?? '',
        quantity: _int(row['quantity']) ?? 0,
        subtotal: parseAmount(row['subtotal']),
        isProrated: row['is_prorated'] == true,
      );

  static StorageUsage storageFromJson(Object? body) {
    if (body is! Map) return const StorageUsage();
    return StorageUsage(
      usedDisplay: _str(body['used_display']) ?? '',
      limitDisplay: _str(body['limit_display']),
      percent: body['percent'] is num ? (body['percent'] as num).toDouble() : null,
      // Explicit flag first; a null cap says the same thing.
      unlimited: body['unlimited'] == true || body['limit_bytes'] == null,
    );
  }

  static BillingPlan planFromJson(Map<String, dynamic> row) {
    final features = row['features'];
    return BillingPlan(
      id: _str(row['plan_id']) ?? '',
      name: _str(row['name']) ?? '',
      description: _str(row['description']) ?? '',
      monthlyPerUser: parseAmount(row['monthly_price_per_user']),
      annualPerUser: parseAmount(row['annual_price_per_user']),
      minUsers: _int(row['min_users']),
      maxUsers: _int(row['max_users']),
      features: features is Map
          ? {for (final e in features.entries) '${e.key}': e.value}
          : const {},
    );
  }

  static String? _str(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  static int? _int(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
