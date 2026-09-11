import 'package:flutter/material.dart';

import '../models/country_code.dart';
import '../utils/phone_rules.dart';

/// Owns one phone field's country + national-digits state, so a screen with a
/// contact-number box no longer has to track a plain [TextEditingController]
/// and a hardcoded `+91` separately — the two travel together and the caller
/// only ever needs one object.
///
/// Notifies on every change (country picked, digits typed) so [PhoneInputField]
/// can rebuild; a screen that needs to know "is this field usable yet" reads
/// [isComplete]/[isBlank] the same way it read `PhoneFormat.isComplete` before.
class PhoneController extends ChangeNotifier {
  PhoneController({String? initialE164}) : _pendingSeed = initialE164 {
    digits.addListener(notifyListeners);
  }

  /// Defaults to India — every contact-number field in the app defaulted to
  /// `+91` before this picker existed, so a blank field keeps behaving the
  /// same way until the user (or a seeded record) says otherwise.
  String iso2 = 'IN';
  String dialCode = '+91';
  final TextEditingController digits = TextEditingController();

  String? _pendingSeed;
  bool _seeded = false;

  /// Supplies (or replaces) the raw value to seed from, for a caller that
  /// only learns the record's stored value after construction — an async
  /// detail fetch not yet resolved when the controller itself had to be
  /// created (it is a field initializer, evaluated before any network
  /// response can exist). A no-op once already seeded, matching [seedOnce]'s
  /// own "never overwrite what's already there" contract.
  void setPendingSeed(String? raw) {
    if (_seeded) return;
    _pendingSeed = raw;
  }

  /// Splits a stored E.164-ish value ("+917045090267") into country +
  /// national digits, once the country list has loaded. Matched by longest
  /// dial-code prefix, since some codes share a leading digit (+1 vs +91) —
  /// the shortest match would misassign every +91 number to some +9-prefixed
  /// country if one existed. One-shot: a later call is a no-op, so a
  /// catalog that finishes loading after the user has already started typing
  /// never overwrites them.
  void seedOnce(List<CountryCode> countries) {
    if (_seeded) return;
    _seeded = true;
    final raw = _pendingSeed?.trim();
    if (raw == null || raw.isEmpty) return;

    CountryCode? match;
    for (final c in countries) {
      if (c.dialCode.isEmpty || !raw.startsWith(c.dialCode)) continue;
      if (match == null || c.dialCode.length > match.dialCode.length) match = c;
    }
    if (match != null) {
      iso2 = match.iso2;
      dialCode = match.dialCode;
      digits.text = raw.substring(match.dialCode.length).replaceAll(RegExp(r'\D'), '');
    } else {
      // Unrecognised prefix — keep the default country rather than guess, but
      // still surface the digits so nothing the record held silently vanishes.
      digits.text = raw.replaceAll(RegExp(r'\D'), '');
    }
    notifyListeners();
  }

  void selectCountry(CountryCode c) {
    if (c.iso2 == iso2 && c.dialCode == dialCode) return;
    iso2 = c.iso2;
    dialCode = c.dialCode;
    // A number typed for the old country is rarely valid for the new one
    // (different digit count, different area-code shape) — clearing it is
    // more honest than leaving digits that look complete but are not.
    digits.clear();
    notifyListeners();
  }

  bool get isBlank => digits.text.trim().isEmpty;

  bool get isComplete => phoneRuleFor(iso2).accepts(digits.text.trim().length);

  PhoneRule get rule => phoneRuleFor(iso2);

  /// The value to send: dial code concatenated with the national digits, or
  /// null when the field was left empty (phone is optional almost everywhere
  /// — see `PhoneFormat`, the pattern this class replaces).
  String? toE164() => isBlank ? null : '$dialCode${digits.text.trim()}';

  @override
  void dispose() {
    digits.dispose();
    super.dispose();
  }
}
