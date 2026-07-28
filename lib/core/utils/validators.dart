/// Input and business validators.
///
/// Every method returns `null` when the value is acceptable, or a
/// user-facing message when it is not — the shape Flutter's form
/// `validator:` callbacks expect, so these drop straight into
/// `AppTextField(errorText: ...)`.
///
/// Flutter Coding Standards §9: client-side validation is a convenience, not a
/// guarantee. The backend must validate everything again.
class Validators {
  const Validators._();

  // ── Patterns (named so no magic strings appear at call sites) ──

  /// Pragmatic email shape check — one `@`, a dot in the domain, no spaces.
  static final RegExp emailPattern = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  /// Indian mobile number: optional +91/0 prefix, then 6-9 and nine digits.
  static final RegExp phonePattern = RegExp(r'^(?:\+91|0)?[6-9]\d{9}$');

  /// GSTIN: 2 state digits, 10-char PAN, entity digit, 'Z', checksum char.
  static final RegExp gstinPattern =
      RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z]\d[Z][A-Z\d]$');

  /// Characters stripped before validating a phone number.
  static final RegExp _phoneSeparators = RegExp(r'[\s()-]');

  /// Longest accepted single-line free-text value.
  static const int maxNameLength = 120;

  /// Fails when [value] is null, empty or only whitespace.
  ///
  /// [fieldLabel] is interpolated into the message, e.g. "Company is required".
  static String? required(String? value, {String fieldLabel = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$fieldLabel is required';
    return null;
  }

  /// Validates an email address. Empty is allowed unless [isRequired].
  static String? email(String? value, {bool isRequired = false}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return isRequired ? 'Email is required' : null;
    }
    if (!emailPattern.hasMatch(trimmed)) return 'Enter a valid email address';
    return null;
  }

  /// Validates an Indian mobile number. Empty is allowed unless [isRequired].
  static String? phone(String? value, {bool isRequired = false}) {
    final trimmed = (value ?? '').replaceAll(_phoneSeparators, '').trim();
    if (trimmed.isEmpty) {
      return isRequired ? 'Phone number is required' : null;
    }
    if (!phonePattern.hasMatch(trimmed)) return 'Enter a valid mobile number';
    return null;
  }

  /// Validates a GSTIN. Empty is allowed unless [isRequired].
  static String? gstin(String? value, {bool isRequired = false}) {
    final trimmed = value?.trim().toUpperCase() ?? '';
    if (trimmed.isEmpty) {
      return isRequired ? 'GSTIN is required' : null;
    }
    if (!gstinPattern.hasMatch(trimmed)) return 'Enter a valid 15-digit GSTIN';
    return null;
  }

  /// Validates a positive monetary amount.
  static String? amount(String? value, {bool isRequired = true}) {
    final trimmed = value?.trim().replaceAll(',', '') ?? '';
    if (trimmed.isEmpty) {
      return isRequired ? 'Amount is required' : null;
    }
    final parsed = num.tryParse(trimmed);
    if (parsed == null) return 'Enter a valid amount';
    if (parsed <= 0) return 'Amount must be greater than zero';
    return null;
  }

  /// Validates a free-text name / title of at most [maxNameLength] characters.
  static String? name(String? value, {String fieldLabel = 'Name'}) {
    final requiredError = required(value, fieldLabel: fieldLabel);
    if (requiredError != null) return requiredError;
    if (value!.trim().length > maxNameLength) {
      return '$fieldLabel must be $maxNameLength characters or fewer';
    }
    return null;
  }

  /// Runs [validators] in order and returns the first failure, if any.
  static String? firstError(
    String? value,
    List<String? Function(String?)> validators,
  ) {
    for (final validate in validators) {
      final error = validate(value);
      if (error != null) return error;
    }
    return null;
  }
}
