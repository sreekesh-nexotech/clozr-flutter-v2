import 'package:equatable/equatable.dart';

/// A warning attached to a document, preview or form.
///
/// The backend sends a machine code plus context and **no** message text
/// (handover §4) — the copy lives in `accounting_copy.dart`. Older rows may
/// send a bare string, which becomes a warning with that string as its code.
class DocWarning extends Equatable {
  const DocWarning(this.code, [this.data = const {}]);

  final String code;
  final Map<String, dynamic> data;

  @override
  List<Object?> get props => [code, data];
}

/// One line of an accounting document (handover §8.3 "Line").
class AccDocumentLine extends Equatable {
  const AccDocumentLine({
    required this.lineNo,
    this.productId,
    this.description = '',
    this.hsnSac,
    this.supplyNature,
    this.qty = '1',
    this.unit,
    this.unitPrice = '0',
    this.lineDiscount,
    this.taxable,
    this.taxTreatment,
    this.ratePct,
    this.cessPct,
    this.rateVariantKey,
    this.rateMatchLevel,
    this.taxCgst,
    this.taxSgst,
    this.taxIgst,
    this.taxCess,
  });

  final int lineNo;
  final String? productId;
  final String description;
  final String? hsnSac;
  final String? supplyNature;

  /// Decimal strings, exactly as sent.
  final String qty;
  final String? unit;
  final String unitPrice;
  final String? lineDiscount;
  final String? taxable;
  final String? taxTreatment;
  final String? ratePct;
  final String? cessPct;
  final String? rateVariantKey;
  final String? rateMatchLevel;
  final String? taxCgst;
  final String? taxSgst;
  final String? taxIgst;
  final String? taxCess;

  @override
  List<Object?> get props => [lineNo, description, qty, unitPrice, taxable];
}

/// One tax line (a head × direction) on a document.
class AccTaxLine extends Equatable {
  const AccTaxLine({
    required this.head,
    this.direction,
    this.amount = '0',
    this.ratePct,
    this.itcStatus,
  });

  final String head; // CGST | SGST | IGST | CESS
  final String? direction;
  final String amount;
  final String? ratePct;
  final String? itcStatus;

  @override
  List<Object?> get props => [head, direction, amount, ratePct, itcStatus];
}

/// A sales or purchase document — invoices, notes, vouchers and vendor bills
/// all share this row (handover §8.3; list and detail are identical).
///
/// Money fields are the API's decimal strings. Draft totals are provisional:
/// the server recomputes them at issue, so the UI labels them "estimated"
/// until [isIssued].
class AccDocument extends Equatable {
  const AccDocument({
    required this.id,
    required this.docType,
    this.direction = 'OUTWARD',
    this.number,
    this.documentDate,
    this.supplyDate,
    this.tosDate,
    this.postingDate,
    this.dueDate,
    this.customerId,
    this.vendorId,
    this.vendorInvoiceNo,
    this.rcmApplies = false,
    this.tdsAmount,
    this.payable,
    this.paidAmount,
    this.placeOfSupply,
    this.supply,
    this.transactionClass,
    this.amountsAre,
    this.currency = 'INR',
    this.taxableTotal = '0',
    this.taxCgst = '0',
    this.taxSgst = '0',
    this.taxIgst = '0',
    this.taxCess = '0',
    this.roundOff = '0',
    this.grandTotal = '0',
    this.status = 'DRAFT',
    this.issuedAt,
    this.cancelledAt,
    this.cancelReason,
    this.paymentState = 'NA',
    this.openBalance,
    this.settledBy,
    this.referencesDocument,
    this.reasonCode,
    this.withGst,
    this.sourceType,
    this.sourceId,
    this.quotationId,
    this.paymentPlanId,
    this.paymentRecordId,
    this.projectId,
    this.narration,
    this.terms,
    this.notes,
    this.warnings = const [],
    this.configDraftRows = 0,
    this.partySnapshot = const {},
    this.lines = const [],
    this.taxLines = const [],
  });

  final String id;
  final String docType;
  final String direction;

  /// Null until issued — a draft has no number.
  final String? number;
  final String? documentDate;
  final String? supplyDate;
  final String? tosDate;
  final String? postingDate;
  final String? dueDate;
  final String? customerId;
  final String? vendorId;
  final String? vendorInvoiceNo;
  final bool rcmApplies;
  final String? tdsAmount;
  final String? payable;
  final String? paidAmount;
  final String? placeOfSupply;
  final String? supply;
  final String? transactionClass;
  final String? amountsAre;
  final String currency;
  final String taxableTotal;
  final String taxCgst;
  final String taxSgst;
  final String taxIgst;
  final String taxCess;
  final String roundOff;
  final String grandTotal;
  final String status;
  final String? issuedAt;
  final String? cancelledAt;
  final String? cancelReason;
  final String paymentState;
  final String? openBalance;
  final String? settledBy;
  final String? referencesDocument;
  final String? reasonCode;
  final bool? withGst;
  final String? sourceType;
  final String? sourceId;
  final String? quotationId;
  final String? paymentPlanId;
  final String? paymentRecordId;
  final String? projectId;
  final String? narration;
  final String? terms;
  final String? notes;
  final List<DocWarning> warnings;

  /// How many unverified config rows were used — a notice, not an error.
  final int configDraftRows;

  /// The frozen party identity at issue (`gstin`, registration, state, and on
  /// notes the `settlement` split). Display only.
  final Map<String, dynamic> partySnapshot;
  final List<AccDocumentLine> lines;
  final List<AccTaxLine> taxLines;

  bool get isDraft => status == 'DRAFT';
  bool get isIssued => status == 'ISSUED';
  bool get isCancelled => status == 'CANCELLED';
  bool get isVoid => status == 'VOID_DRAFT';
  bool get isInward => direction == 'INWARD';

  /// The party this document is with — customer outward, vendor inward.
  String? get partyId => isInward ? vendorId : customerId;

  /// The number when issued, otherwise a stand-in the UI can show.
  String get displayNumber => (number == null || number!.isEmpty)
      ? (isVoid ? 'Void draft' : 'Draft')
      : number!;

  /// Whether this is an outward invoice a credit note can be raised against.
  bool get canCreditNote =>
      isIssued &&
      !isInward &&
      const {'TAX_INVOICE', 'BILL_OF_SUPPLY', 'EXPORT_INVOICE'}.contains(docType);

  @override
  List<Object?> get props => [id, status, number, grandTotal, openBalance, paymentState];
}

/// `POST documents/{id}/preview-tax/` — what the document would be if issued
/// now. Side-effect free.
class TaxPreview extends Equatable {
  const TaxPreview({
    this.supply,
    this.transactionClass,
    this.amountsAre,
    this.lines = const [],
    this.totals = const {},
    this.configRows = const [],
    this.warnings = const [],
  });

  final String? supply;
  final String? transactionClass;
  final String? amountsAre;
  final List<TaxPreviewLine> lines;

  /// `taxable_total, tax_cgst, tax_sgst, tax_igst, tax_cess, round_off,
  /// grand_total` as money strings.
  final Map<String, String> totals;
  final List<ConfigRow> configRows;
  final List<DocWarning> warnings;

  @override
  List<Object?> get props => [supply, transactionClass, lines, totals, warnings];
}

class TaxPreviewLine extends Equatable {
  const TaxPreviewLine({
    required this.lineNo,
    this.hsnSac,
    this.taxable,
    this.ratePct,
    this.variantKey,
    this.matchLevel,
    this.treatment,
  });

  final int lineNo;
  final String? hsnSac;
  final String? taxable;

  /// Null when the line resolved to no rate row.
  final String? ratePct;
  final String? variantKey;
  final String? matchLevel;
  final String? treatment;

  @override
  List<Object?> get props => [lineNo, hsnSac, taxable, ratePct, variantKey];
}

/// A tax-config row a preview relied on, with its verification state.
class ConfigRow extends Equatable {
  const ConfigRow({this.hsnSac, this.ratePct, this.verificationStatus});

  final String? hsnSac;
  final String? ratePct;
  final String? verificationStatus;

  bool get isVerified => (verificationStatus ?? '').toUpperCase() == 'VERIFIED';

  @override
  List<Object?> get props => [hsnSac, ratePct, verificationStatus];
}

/// One rate variant from `GET masters/hsn-rates/` or from the
/// `RATE_VARIANT_REQUIRED` conflict's `cause.candidates`.
class RateVariant extends Equatable {
  const RateVariant({
    required this.variantKey,
    this.hsnSac,
    this.ratePct,
    this.description,
    this.isDefault = false,
  });

  final String variantKey;
  final String? hsnSac;
  final String? ratePct;
  final String? description;
  final bool isDefault;

  @override
  List<Object?> get props => [variantKey, hsnSac, ratePct];
}

/// A page of documents.
class AccDocumentPage {
  const AccDocumentPage({required this.results, this.count = 0, this.hasMore = false});

  final List<AccDocument> results;
  final int count;
  final bool hasMore;
}

/// `GET documents/{id}/render-context/` — the print payload.
class InvoicePrint {
  const InvoicePrint(this.raw);

  /// Kept whole: it is a flat display payload, read field by field.
  final Map<String, dynamic> raw;

  String s(String key) {
    final v = raw[key];
    return v == null ? '' : '$v';
  }

  List<Map<String, dynamic>> get lines => [
        for (final l in (raw['lines'] as List? ?? const []))
          if (l is Map) Map<String, dynamic>.from(l),
      ];
}
