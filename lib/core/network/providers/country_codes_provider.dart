import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_config.dart';
import '../../models/country_code.dart';
import '../api_endpoints.dart';
import '../network_providers.dart';
import '../paginated.dart';

/// `GET /crm/country-codes/` — every country the phone country-code picker
/// can offer, in the org's own display order. Lives in `core/`, not a feature
/// module, because a contact-number field appears in CRM (Leads, Customers)
/// and People (Members) alike.
///
/// Falls back to [_fallback] in mock mode or on a failed fetch, same
/// "never leave a phone field with no country to pick" reasoning
/// `PhoneFormat` used to bake in as a hardcoded `+91` — a form still needs a
/// usable default when the catalog itself is unreachable.
final countryCodesProvider = FutureProvider<List<CountryCode>>((ref) async {
  if (!ApiConfig.apiEnabled) return _fallback;
  final api = ref.watch(apiServiceProvider);
  try {
    final body = await api.get(ApiEndpoints.countryCodes, query: const {'page_size': 300});
    final rows = Paginated.fromAny<CountryCode>(body, CountryCode.fromJson).results;
    final active = rows.where((c) => c.iso2.isNotEmpty && c.dialCode.isNotEmpty).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return active.isEmpty ? _fallback : active;
  } on Object {
    return _fallback;
  }
});

/// India first — every existing contact-number field defaulted to `+91`
/// before this picker existed, so a fetch failure should not change what a
/// blank field defaults to.
const _fallback = [
  CountryCode(id: 'fallback-in', iso2: 'IN', name: 'India', dialCode: '+91', flag: '🇮🇳'),
  CountryCode(id: 'fallback-us', iso2: 'US', name: 'United States', dialCode: '+1', flag: '🇺🇸'),
  CountryCode(id: 'fallback-gb', iso2: 'GB', name: 'United Kingdom', dialCode: '+44', flag: '🇬🇧'),
  CountryCode(id: 'fallback-ae', iso2: 'AE', name: 'United Arab Emirates', dialCode: '+971', flag: '🇦🇪'),
  CountryCode(id: 'fallback-sg', iso2: 'SG', name: 'Singapore', dialCode: '+65', flag: '🇸🇬'),
];
