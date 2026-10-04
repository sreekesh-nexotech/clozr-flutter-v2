import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/app_error.dart';
import '../../../domain/entities/acc_masters.dart';
import '../../../domain/entities/acc_setup.dart';
import 'acc_remote_support.dart';
import 'accounting_mappers.dart';

/// Masters and setup reads (`/accounting/masters/…`, `/accounting/setup/…`,
/// handover §8.1–8.2), plus the org-wide states lookup.
class AccountingMastersRemoteDataSource {
  const AccountingMastersRemoteDataSource(this._api);

  final ApiService _api;

  // ── Setup (not behind the activation gate) ──

  /// Null when the profile was never created (404).
  Future<TenantProfile?> tenantProfile() async {
    try {
      final res = await _api.get(ApiEndpoints.accTenantProfile);
      return res is Map ? mapTenantProfile(Map<String, dynamic>.from(res)) : null;
    } on AppError catch (e) {
      if (e.type == AppErrorType.notFound) return null;
      rethrow;
    }
  }

  Future<List<TenantAttribute>> tenantAttributes() async {
    final res = await _api.get(ApiEndpoints.accTenantAttributes);
    return mapTenantAttributes(res is Map ? res['results'] : res);
  }

  /// Null without a profile (404).
  Future<GatesReport?> gates() async {
    try {
      final res = await _api.get(ApiEndpoints.accGates);
      return res is Map ? mapGates(Map<String, dynamic>.from(res)) : null;
    } on AppError catch (e) {
      if (e.type == AppErrorType.notFound) return null;
      rethrow;
    }
  }

  /// `{features: {accounting: bool, …}}` → the keys that are on.
  Future<Set<String>> myFeatures() async {
    final res = await _api.get(ApiEndpoints.myFeatures);
    final features = res is Map ? res['features'] : null;
    if (features is Map) {
      return {for (final e in features.entries) if (e.value == true) '${e.key}'};
    }
    if (features is List) return {for (final f in features) '$f'};
    return const {};
  }

  /// The cheapest activation probe for a user without `acc_setup` (§2): a
  /// one-row document read. True when it answers, false on
  /// `ACCOUNTING_NOT_ACTIVE`; anything else propagates.
  Future<bool> probeActive(String path) async {
    try {
      await _api.get(path, query: {'page_size': 1});
      return true;
    } on AppError catch (e) {
      if (e.isAccountingInactive) return false;
      rethrow;
    }
  }

  Future<List<GstState>> states() async {
    final res = await _api.get(ApiEndpoints.states);
    return mapStates(res is Map ? res['results'] : res);
  }

  // ── Vendors ──

  Future<RawPage> fetchVendorPage({String? search, bool? active, int page = 1, int pageSize = 100}) async {
    final res = await _api.get(ApiEndpoints.accVendors,
        query: compact({
          'search': search,
          'is_active': active == null ? null : '$active',
          'page': page,
          'page_size': pageSize,
        }));
    return RawPage.from(res);
  }

  Future<Vendor?> fetchVendor(String id) async {
    final res = await _api.get(ApiEndpoints.accVendor(id));
    return res is Map ? mapVendor(Map<String, dynamic>.from(res)) : null;
  }

  Future<Vendor?> createVendor(Map<String, Object?> fields) async {
    final res = await _api.post(ApiEndpoints.accVendors, body: fields);
    return res is Map ? mapVendor(Map<String, dynamic>.from(res)) : null;
  }

  Future<Vendor?> updateVendor(String id, Map<String, Object?> fields) async {
    final res = await _api.patch(ApiEndpoints.accVendor(id), body: fields);
    return res is Map ? mapVendor(Map<String, dynamic>.from(res)) : null;
  }

  Future<void> deleteVendor(String id) => _api.delete(ApiEndpoints.accVendor(id));

  // ── Tax profiles ──

  /// [kind] is `customer` or `vendor`. 404 → [PartyTaxProfile.empty].
  Future<PartyTaxProfile> partyTaxProfile(String kind, String id) async {
    try {
      final res = await _api.get(ApiEndpoints.accPartyTaxProfile(kind, id));
      return res is Map ? mapPartyTaxProfile(Map<String, dynamic>.from(res)) : PartyTaxProfile.empty;
    } on AppError catch (e) {
      if (e.type == AppErrorType.notFound) return PartyTaxProfile.empty;
      rethrow;
    }
  }

  Future<PartyTaxProfile> savePartyTaxProfile(String kind, String id, Map<String, Object?> body) async {
    final res = await _api.put(ApiEndpoints.accPartyTaxProfile(kind, id), body: compact(body));
    return res is Map ? mapPartyTaxProfile(Map<String, dynamic>.from(res)) : PartyTaxProfile.empty;
  }

  /// Batch B2B lookup for list badges — up to 200 ids.
  Future<Map<String, bool>> customerB2bFlags(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final res = await _api.get(ApiEndpoints.accCustomerTaxProfiles,
        query: {'ids': ids.take(200).join(',')});
    final rows = res is Map ? res['results'] : null;
    return {
      if (rows is List)
        for (final r in rows)
          if (r is Map && r['customer_id'] != null) '${r['customer_id']}': r['is_b2b'] == true,
    };
  }

  Future<ProductTaxProfile> productTaxProfile(String productId) async {
    try {
      final res = await _api.get(ApiEndpoints.accProductTaxProfile(productId));
      return res is Map ? mapProductTaxProfile(Map<String, dynamic>.from(res)) : ProductTaxProfile.empty;
    } on AppError catch (e) {
      if (e.type == AppErrorType.notFound) return ProductTaxProfile.empty;
      rethrow;
    }
  }

  Future<ProductTaxProfile> saveProductTaxProfile(String productId, Map<String, Object?> body) async {
    final res = await _api.put(ApiEndpoints.accProductTaxProfile(productId), body: body);
    return res is Map ? mapProductTaxProfile(Map<String, dynamic>.from(res)) : ProductTaxProfile.empty;
  }

  // ── Bank accounts ──

  Future<List<BankAccount>> bankAccounts() async {
    final res = await _api.get(ApiEndpoints.accBankAccounts,
        query: {'is_active': 'true', 'page_size': 200});
    return mapBankAccounts(res is Map ? res['results'] : res);
  }
}
