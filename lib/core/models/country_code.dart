/// One row of `GET /crm/country-codes/` — a dialable country, for the phone
/// country-code picker every contact-number field shares.
class CountryCode {
  const CountryCode({
    required this.id,
    required this.iso2,
    required this.name,
    required this.dialCode,
    required this.flag,
    this.position = 0,
  });

  final String id;

  /// Two-letter ISO code ("IN", "US") — what [PhoneRules] keys its per-country
  /// digit-length table on, since [dialCode] alone is ambiguous (+1 is both
  /// the US and Canada, with different area-code conventions but the same
  /// digit count either way).
  final String iso2;

  final String name;

  /// "+91" — carries the leading `+`, so it concatenates directly onto the
  /// national digits to form the E.164 value the API stores.
  final String dialCode;

  final String flag;

  /// The org's own display order for the picker list.
  final int position;

  factory CountryCode.fromJson(Map<String, dynamic> json) => CountryCode(
        id: (json['country_code_id'] ?? '').toString(),
        iso2: (json['iso2'] ?? '').toString().toUpperCase(),
        name: (json['name'] ?? '').toString(),
        dialCode: (json['dial_code'] ?? '').toString(),
        flag: (json['flag'] ?? '').toString(),
        position: (json['position'] as num?)?.toInt() ?? 0,
      );
}
