import 'package:equatable/equatable.dart';

/// Where the organisation stands with accounting, as far as this user can
/// tell. Resolved once per session from the three pre-checks in handover §2 —
/// never from error bodies.
enum AccountingStatus {
  /// Still resolving.
  unknown,

  /// Mock mode — there is no backend to ask.
  unavailable,

  /// The user holds no `acc_*` permission.
  noAccess,

  /// The subscription plan does not include accounting.
  notInPlan,

  /// Set up but not (yet) activated, or never set up at all.
  inactive,

  /// Activating or suspended — the books exist but are not open for posting.
  paused,

  /// Open for business.
  active,
}

/// `GET setup/tenant-profile/` — read-only on mobile (the web wizard owns it).
class TenantProfile extends Equatable {
  const TenantProfile({
    this.activationStatus = 'INACTIVE',
    this.entityType,
    this.legalName,
    this.pan,
    this.tan,
    this.stateCode,
    this.ledgerStartDate,
    this.defaultAmountsAre,
    this.defaultBillingMode,
    this.returnFrequency,
    this.activatedAt,
  });

  final String activationStatus;
  final String? entityType;
  final String? legalName;
  final String? pan;
  final String? tan;
  final String? stateCode;
  final String? ledgerStartDate;
  final String? defaultAmountsAre;
  final String? defaultBillingMode;
  final String? returnFrequency;
  final String? activatedAt;

  @override
  List<Object?> get props => [activationStatus, entityType, stateCode, ledgerStartDate];
}

/// One effective-dated tenant attribute (GSTIN, registration, TDS deductor…).
class TenantAttribute extends Equatable {
  const TenantAttribute({required this.attribute, this.value, this.effectiveFrom, this.effectiveTo});

  final String attribute;
  final Object? value;
  final String? effectiveFrom;
  final String? effectiveTo;

  bool get isCurrent => effectiveTo == null || effectiveTo!.isEmpty;

  /// The value unwrapped from its JSON envelope (`{"gstin": "…"}`,
  /// `{"value": true}`, `{"status": "REGISTERED"}`), or the bare scalar an
  /// older row holds.
  String get display {
    final v = value;
    if (v is Map) {
      for (final k in const ['gstin', 'status', 'type', 'value', 'state_code']) {
        if (v.containsKey(k)) return _scalar(v[k]);
      }
      return v.values.map(_scalar).join(', ');
    }
    return _scalar(v);
  }

  static String _scalar(Object? v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'Yes' : 'No';
    return '$v';
  }

  @override
  List<Object?> get props => [attribute, value, effectiveFrom, effectiveTo];
}

class GateResult extends Equatable {
  const GateResult({required this.gate, this.passed = false, this.detail});

  final String gate; // G1…G10
  final bool passed;
  final String? detail;

  @override
  List<Object?> get props => [gate, passed, detail];
}

/// `GET setup/gates/`.
class GatesReport extends Equatable {
  const GatesReport({this.gates = const [], this.canActivate = false, this.activationStatus});

  final List<GateResult> gates;
  final bool canActivate;
  final String? activationStatus;

  @override
  List<Object?> get props => [gates, canActivate, activationStatus];
}
