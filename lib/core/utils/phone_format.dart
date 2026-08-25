import 'package:flutter/services.dart';

/// One place deciding what a phone number looks like on screen and on the wire.
///
/// The backend stores the country code **inside** the number and leaves the
/// separate `*_country_code` columns null — a live lead reads
/// `"mobile_no": "+917045090267"` with `"mobile_country_code": null`. So the
/// app sends `+91` concatenated with ten digits, never a bare ten and never a
/// spaced or hyphenated form.
///
/// The UI shows `+91` as a **prefix** rather than putting it in the text field:
/// a prefix cannot be backspaced over, duplicated by a user who types their own
/// `+91`, or lost when the field is cleared.
class PhoneFormat {
  PhoneFormat._();

  /// The only country the product ships to today. Kept as a constant rather
  /// than scattered string literals so adding a picker later has one place to
  /// change.
  static const String dialCode = '+91';

  /// Indian subscriber numbers are exactly ten digits.
  static const int nationalDigits = 10;

  /// Keystroke rules for a phone input: digits only, capped at ten.
  ///
  /// Both are needed. `TextInputType.phone` picks the on-screen keyboard — it
  /// still offers `+ * #`, and a paste ignores it entirely.
  static List<TextInputFormatter> get inputFormatters => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(nationalDigits),
      ];

  /// The ten national digits held in a field, given whatever is in it.
  ///
  /// Tolerant of stored values that already carry the code or separators —
  /// `+91 98470 11001`, `919847011001` and `9847011001` all yield the same ten
  /// — so an existing record can be loaded into the field without doubling up.
  static String national(String? raw) {
    var digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    // Strip a leading country code, then the trunk '0' some numbers carry.
    if (digits.length > nationalDigits && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    if (digits.length > nationalDigits && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    // Keep the last ten: a longer string is more likely to have junk at the
    // front (an extra code) than at the end.
    return digits.length <= nationalDigits
        ? digits
        : digits.substring(digits.length - nationalDigits);
  }

  /// Whether [raw] holds a complete national number. An empty field is **not**
  /// invalid — phone is optional almost everywhere.
  static bool isComplete(String? raw) =>
      national(raw).length == nationalDigits;

  static bool isBlank(String? raw) => national(raw).isEmpty;

  /// The value to send: `+91XXXXXXXXXX`, or null when the field is empty.
  ///
  /// Returns null rather than a partial number — sending five digits would
  /// store something no one can dial.
  static String? forApi(String? raw) {
    final digits = national(raw);
    return digits.length == nationalDigits ? '$dialCode$digits' : null;
  }
}
