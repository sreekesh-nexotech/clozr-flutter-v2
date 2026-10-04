import 'package:equatable/equatable.dart';

/// A supplier (`masters/vendors/`, handover §8.2).
class Vendor extends Equatable {
  const Vendor({
    required this.id,
    required this.name,
    this.legalName,
    this.email,
    this.phone,
    this.address,
    this.stateCode,
    this.bankAccountNoMasked,
    this.ifsc,
    this.isBodyCorporate = false,
    this.isGtaFcmOpted = false,
    this.isSmallTransporterDeclared = false,
    this.isActive = true,
    this.notes,
  });

  final String id;
  final String name;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? address;
  final String? stateCode;
  final String? bankAccountNoMasked;
  final String? ifsc;
  final bool isBodyCorporate;
  final bool isGtaFcmOpted;
  final bool isSmallTransporterDeclared;
  final bool isActive;
  final String? notes;

  @override
  List<Object?> get props => [id, name, legalName, stateCode, isActive];
}

/// A customer's or vendor's tax identity. The API answers 404 when none was
/// ever saved, which the app treats as "unregistered, no GSTIN" (handover
/// §8.2) — that is [PartyTaxProfile.empty], not an error.
class PartyTaxProfile extends Equatable {
  const PartyTaxProfile({
    this.exists = true,
    this.registrationType,
    this.gstin,
    this.stateCode,
    this.pan,
    this.entityKind,
    this.tdsApplicable = false,
    this.isBodyCorporate = false,
    this.currency,
    this.tdsNatureDefault,
  });

  static const empty = PartyTaxProfile(exists: false);

  final bool exists;
  final String? registrationType;
  final String? gstin;
  final String? stateCode;
  final String? pan;
  final String? entityKind;
  final bool tdsApplicable;
  final bool isBodyCorporate;
  final String? currency;
  final String? tdsNatureDefault;

  bool get isB2b =>
      registrationType == 'REGISTERED' && (gstin ?? '').isNotEmpty;

  @override
  List<Object?> get props =>
      [exists, registrationType, gstin, stateCode, pan, entityKind, tdsApplicable, tdsNatureDefault];
}

/// A product's accounting tax defaults (handover §8.2).
class ProductTaxProfile extends Equatable {
  const ProductTaxProfile({
    this.exists = true,
    this.taxTreatmentDefault,
    this.rateVariantKey,
    this.isRcmOutward = false,
    this.cessApplicable = false,
  });

  static const empty = ProductTaxProfile(exists: false);

  final bool exists;
  final String? taxTreatmentDefault;
  final String? rateVariantKey;
  final bool isRcmOutward;
  final bool cessApplicable;

  @override
  List<Object?> get props =>
      [exists, taxTreatmentDefault, rateVariantKey, isRcmOutward, cessApplicable];
}

/// A bank / cash / gateway account money can move through.
class BankAccount extends Equatable {
  const BankAccount({
    required this.id,
    required this.name,
    this.kind = 'BANK',
    this.accountNoMasked,
    this.provider,
    this.isDefault = false,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String kind; // BANK | CASH | GATEWAY
  final String? accountNoMasked;
  final String? provider;
  final bool isDefault;
  final bool isActive;

  String get label => (accountNoMasked ?? '').isEmpty ? name : '$name · $accountNoMasked';

  @override
  List<Object?> get props => [id, name, kind, isDefault, isActive];
}

/// One GST state (`/organizations/states/`).
class GstState extends Equatable {
  const GstState({required this.code, required this.name, this.alpha = ''});

  final String code; // "32"
  final String name; // "Kerala"
  final String alpha; // "KL"

  String get label => '$code · $name';

  @override
  List<Object?> get props => [code];
}
