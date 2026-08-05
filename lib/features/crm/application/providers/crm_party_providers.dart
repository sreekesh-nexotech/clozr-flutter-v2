import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../domain/entities/customer.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import 'customers_providers.dart';

/// Builds a [CrmPartyLookup] over the *real* customers (API mode). Keyed by
/// `customer_id`; an unknown id — or a lead-only reference — resolves to `null`
/// so the finance name helpers fall back to the raw id / em-dash instead of a
/// fabricated prototype name. Pure and Riverpod-free so it is directly testable.
CrmPartyLookup customerPartyLookup(List<Customer> customers) {
  final byId = <String, CrmParty>{
    for (final c in customers) c.id: CrmParty(c.id, c.name, c.company ?? ''),
  };
  return ({String? custId, String? leadId}) =>
      custId == null ? null : byId[custId];
}

/// Resolves a customer/lead reference (`custId` / `leadId`) to a display party
/// for the finance screens (invoices, payments, quotes).
///
/// * **Mock mode** — delegates to [CrmPartyDirectory] so the seed finance
///   screens read byte-for-byte as before.
/// * **API mode** — builds the lookup from the real customers
///   ([customersProvider]) via [customerPartyLookup], so the hardcoded
///   `crm_party_directory` seed is never consulted against a live backend.
final crmPartyLookupProvider = Provider<CrmPartyLookup>((ref) {
  if (!ApiConfig.apiEnabled) {
    return ({String? custId, String? leadId}) =>
        CrmPartyDirectory.resolve(custId: custId, leadId: leadId);
  }
  return customerPartyLookup(ref.watch(customersProvider).valueOrNull ?? const []);
});
