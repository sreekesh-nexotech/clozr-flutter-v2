/// How many national-number digits a complete phone number needs, once the
/// country's dial code is set aside. The backend has no notion of this today
/// (`GET /crm/country-codes/` carries the dial code and flag only) — this is a
/// client-side table, keyed by ISO2 since the dial code alone is ambiguous
/// (+1 is both the US and Canada).
class PhoneRule {
  const PhoneRule(this.min, this.max);

  final int min;
  final int max;

  bool accepts(int digitCount) => digitCount >= min && digitCount <= max;
}

/// Numbers confirmed against the product's supported markets. Anything not
/// listed falls back to [_default] — the global ITU-T E.164 ceiling (15
/// digits total, so at most 14-ish national digits once a multi-digit dial
/// code is set aside; kept at a flat 15 rather than doing that subtraction
/// per-country, since E.164 itself does not fix a national-number minimum).
const Map<String, PhoneRule> _rulesByIso2 = {
  'IN': PhoneRule(10, 10), // India
  'US': PhoneRule(10, 10), // USA (NANP)
  'CA': PhoneRule(10, 10), // Canada (NANP)
  'GB': PhoneRule(10, 11), // UK — varies by number type
  'CN': PhoneRule(11, 11), // China (mobile)
  'DE': PhoneRule(10, 11), // Germany — varies
  'FR': PhoneRule(9, 9), // France — after the leading 0
  'BR': PhoneRule(10, 11), // Brazil
  'AE': PhoneRule(9, 9), // UAE
  'SG': PhoneRule(8, 8), // Singapore
  'JP': PhoneRule(10, 11), // Japan — mobile is 11 with a leading 0
};

const _default = PhoneRule(4, 15);

/// The digit-length rule for [iso2], or the generic E.164 ceiling for a
/// country not in the confirmed table above.
PhoneRule phoneRuleFor(String iso2) => _rulesByIso2[iso2.toUpperCase()] ?? _default;

/// "Enter 10 digits" / "Enter 8–11 digits" — every phone field's incomplete-
/// number error, phrased for whichever rule the selected country carries.
String phoneDigitsMessage(PhoneRule rule) =>
    rule.min == rule.max ? 'Enter ${rule.min} digits' : 'Enter ${rule.min}–${rule.max} digits';
