import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/entities/acc_document.dart';

/// Every user-facing word the accounting screens show for a backend code.
///
/// The API sends machine codes and no text for warnings, and a `detail`
/// sentence plus a `cause` object for guards (handover §4). The client owns
/// the copy, so it lives here in one place rather than scattered per screen.

// ── Enum labels ──

const docTypeLabels = <String, String>{
  'TAX_INVOICE': 'Tax invoice',
  'BILL_OF_SUPPLY': 'Bill of supply',
  'EXPORT_INVOICE': 'Export invoice',
  'CREDIT_NOTE': 'Credit note',
  'DEBIT_NOTE': 'Debit note',
  'RECEIPT_VOUCHER': 'Receipt voucher',
  'REFUND_VOUCHER': 'Refund voucher',
  'SELF_INVOICE': 'Self invoice',
  'PAYMENT_VOUCHER': 'Payment voucher',
  'VENDOR_BILL': 'Vendor bill',
  'VENDOR_CREDIT_NOTE': 'Vendor credit note',
  'VENDOR_DEBIT_NOTE': 'Vendor debit note',
  'PROFORMA': 'Proforma',
};

/// The four types a manual invoice may be created as.
const manualInvoiceTypes = ['TAX_INVOICE', 'BILL_OF_SUPPLY', 'EXPORT_INVOICE', 'PROFORMA'];

const sourceTypeLabels = <String, String>{
  'PLAN_RECORD': 'Payment plan',
  'MILESTONE': 'Milestone',
  'PERIODIC': 'Periodic billing',
  'TICKET': 'Ticket',
  'MANUAL': 'Manual',
  'OPENING': 'Opening balance',
  'EXPENSE_FORM': 'Expense',
  'BANK_FORM': 'Bank form',
  'PROVIDER_BILLING': 'Provider billing',
};

const transactionClassLabels = <String, String>{
  'B2B': 'B2B',
  'B2C': 'B2C',
  'B2CL': 'B2C large',
  'EXPORT_LUT': 'Export (LUT)',
  'EXPORT_WITH_TAX': 'Export with tax',
  'SEZ': 'SEZ',
  'DEEMED': 'Deemed export',
  'RCM_INWARD': 'Reverse charge (inward)',
  'IMPORT_SERVICE': 'Import of service',
  'NON_GST': 'Non-GST',
};

const taxTreatmentLabels = <String, String>{
  'TAXABLE': 'Taxable',
  'NIL': 'Nil rated',
  'EXEMPT': 'Exempt',
  'NON_GST': 'Non-GST',
  'ZERO_RATED': 'Zero rated',
  'RCM_OUTWARD': 'Reverse charge',
};

const supplyNatureLabels = <String, String>{'GOODS': 'Goods', 'SERVICE': 'Service'};

const amountsAreLabels = <String, String>{
  'EXCLUSIVE': 'Tax extra',
  'INCLUSIVE': 'Tax included',
};

const billingModeLabels = <String, String>{
  'INVOICE_ON_DUE': 'Invoice on due date',
  'INVOICE_ON_COMPLETION': 'Invoice on completion',
  'PERIODIC': 'Periodic',
  'MANUAL': 'Manual',
};

/// One line of explanation per billing mode, under the chips.
const billingModeHelp = <String, String>{
  'INVOICE_ON_DUE': 'A draft invoice is created for each instalment on its due date.',
  'INVOICE_ON_COMPLETION': 'Invoiced when the linked project milestone completes.',
  'PERIODIC': 'A draft invoice is created for each billing period.',
  'MANUAL': 'Nothing is created automatically — issue invoices yourself.',
};

const registrationTypeLabels = <String, String>{
  'REGISTERED': 'Registered',
  'UNREGISTERED': 'Unregistered',
  'COMPOSITION': 'Composition',
  'SEZ': 'SEZ',
  'OVERSEAS': 'Overseas',
  'GOVERNMENT': 'Government',
};

const entityKindLabels = <String, String>{
  'INDIVIDUAL_HUF': 'Individual / HUF',
  'COMPANY': 'Company',
  'FIRM': 'Firm',
  'OTHER': 'Other',
};

const entityTypeLabels = <String, String>{
  'PROPRIETOR': 'Proprietorship',
  'PARTNERSHIP': 'Partnership',
  'LLP': 'LLP',
  'PVT_LTD': 'Private limited',
};

const sourceAccountLabels = <String, String>{
  'BANK': 'Bank',
  'CASH': 'Cash',
  'GATEWAY': 'Gateway',
  'OWNER': "Owner's funds",
};

const creditSourceLabels = <String, String>{
  'OVERPAYMENT': 'Overpayment',
  'UNAPPLIED_RECEIPT': 'Unapplied receipt',
  'CREDIT_NOTE_HOLD': 'Credit note',
};

/// One lower-case method vocabulary for both apps (handover §12.11).
const paymentMethods = <String, String>{
  'upi': 'UPI',
  'neft': 'NEFT',
  'imps': 'IMPS',
  'rtgs': 'RTGS',
  'card': 'Card',
  'cheque': 'Cheque',
  'cash': 'Cash',
  'gateway': 'Gateway',
};

String label(Map<String, String> map, String? key) =>
    key == null || key.isEmpty ? '—' : (map[key] ?? _humanise(key));

/// `NOT_IN_2B` → `Not in 2b` — the fallback for a code this table has not met.
String _humanise(String code) {
  final s = code.replaceAll('_', ' ').toLowerCase();
  return s.isEmpty ? code : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ── Seed vocabularies (no endpoint; pack v2026.09.20, handover §7.3) ──

class ExpenseCategory {
  const ExpenseCategory(this.key, this.label, {this.itc = ItcHint.eligible, this.tdsNature});

  final String key;
  final String label;
  final ItcHint itc;

  /// The category's default TDS nature, where the handover documents one
  /// (§7.3 names three; the rest live only in the backend's seed CSV). The
  /// backend applies the default itself — this is display only, so a category
  /// without one here is simply shown without a hint rather than guessed.
  final String? tdsNature;
}

enum ItcHint { eligible, blocked, notApplicable }

const expenseCategories = <ExpenseCategory>[
  ExpenseCategory('RENT_PREMISES', 'Rent — premises', tdsNature: 'RENT_LAND_BUILDING'),
  ExpenseCategory('RENT_EQUIPMENT', 'Rent — equipment'),
  ExpenseCategory('RENT_RESIDENTIAL_STAFF', 'Rent — staff housing'),
  ExpenseCategory('ELECTRICITY_WATER', 'Electricity & water', itc: ItcHint.notApplicable),
  ExpenseCategory('TELECOM_INTERNET', 'Telecom & internet'),
  ExpenseCategory('SOFTWARE_SAAS_DOMESTIC', 'Software / SaaS (India)'),
  ExpenseCategory('SOFTWARE_CLOUD_IMPORTED', 'Software / cloud (imported)'),
  ExpenseCategory('PROFESSIONAL_FEES', 'Professional fees', tdsNature: 'PROFESSIONAL'),
  ExpenseCategory('LEGAL_FEES', 'Legal fees'),
  ExpenseCategory('AUDIT_ACCOUNTING', 'Audit & accounting'),
  ExpenseCategory('TECHNICAL_SERVICES', 'Technical services'),
  ExpenseCategory('CONTRACTORS_JOBWORK', 'Contractors & job work', tdsNature: 'CONTRACTOR'),
  ExpenseCategory('MANPOWER_SUPPLY', 'Manpower supply'),
  ExpenseCategory('SECURITY_SERVICES', 'Security services'),
  ExpenseCategory('HOUSEKEEPING', 'Housekeeping'),
  ExpenseCategory('FREIGHT_GTA', 'Freight (GTA)'),
  ExpenseCategory('COURIER_POSTAGE', 'Courier & postage'),
  ExpenseCategory('ADVERTISING_MARKETING', 'Advertising & marketing'),
  ExpenseCategory('SPONSORSHIP', 'Sponsorship'),
  ExpenseCategory('COMMISSION_BROKERAGE', 'Commission & brokerage'),
  ExpenseCategory('DIRECTOR_FEES', 'Director fees'),
  ExpenseCategory('PARTNER_REMUNERATION', 'Partner remuneration',
      itc: ItcHint.notApplicable),
  ExpenseCategory('STAFF_WELFARE_FOOD', 'Staff welfare & food', itc: ItcHint.blocked),
  ExpenseCategory('STAFF_INSURANCE', 'Staff insurance', itc: ItcHint.blocked),
  ExpenseCategory('TRAVEL_FARES', 'Travel — fares'),
  ExpenseCategory('TRAVEL_HOTEL', 'Travel — hotel'),
  ExpenseCategory('VEHICLE_HIRE', 'Vehicle hire', itc: ItcHint.blocked),
  ExpenseCategory('FUEL', 'Fuel', itc: ItcHint.notApplicable),
  ExpenseCategory('VEHICLE_REPAIRS_INSURANCE', 'Vehicle repairs & insurance', itc: ItcHint.blocked),
  ExpenseCategory('INSURANCE_BUSINESS', 'Business insurance'),
  ExpenseCategory('REPAIRS_BUILDING', 'Repairs — building'),
  ExpenseCategory('REPAIRS_EQUIPMENT', 'Repairs — equipment'),
  ExpenseCategory('PRINTING_STATIONERY', 'Printing & stationery'),
  ExpenseCategory('OFFICE_SUPPLIES', 'Office supplies'),
  ExpenseCategory('GIFTS_SAMPLES', 'Gifts & samples', itc: ItcHint.blocked),
  ExpenseCategory('ENTERTAINMENT_MEALS', 'Entertainment & meals', itc: ItcHint.blocked),
  ExpenseCategory('CLUB_MEMBERSHIP', 'Club membership', itc: ItcHint.blocked),
  ExpenseCategory('CSR', 'CSR', itc: ItcHint.blocked),
  ExpenseCategory('DONATIONS', 'Donations', itc: ItcHint.notApplicable),
  ExpenseCategory('RATES_TAXES_LICENCES', 'Rates, taxes & licences', itc: ItcHint.notApplicable),
  ExpenseCategory('TRAINING_RECRUITMENT', 'Training & recruitment'),
  ExpenseCategory('SUBSCRIPTIONS_TRADE_BODIES', 'Subscriptions & trade bodies'),
  ExpenseCategory('PENALTIES_FINES', 'Penalties & fines', itc: ItcHint.notApplicable),
  ExpenseCategory('MISCELLANEOUS', 'Miscellaneous'),
];

/// TDS natures with their sections — accountants think in sections.
const tdsNatures = <String, String>{
  'SALARY': 'Salary (192)',
  'INTEREST': 'Interest (194A)',
  'CONTRACTOR': 'Contractor (194C)',
  'COMMISSION': 'Commission (194H)',
  'RENT_PLANT': 'Rent — plant (194I(a))',
  'RENT_LAND_BUILDING': 'Rent — land & building (194I(b))',
  'PROFESSIONAL': 'Professional (194J(b))',
  'TECHNICAL': 'Technical (194J(a))',
  'DIRECTOR_FEES': 'Director fees (194J(1)(ba))',
  'PURCHASE_OF_GOODS': 'Purchase of goods (194Q)',
  'PARTNER_REMUNERATION': 'Partner remuneration (194T)',
  'DIVIDEND': 'Dividend (194)',
  'BENEFIT_PERQUISITE': 'Benefit / perquisite (194R)',
  'FOREIGN_PAYMENT': 'Foreign payment (195)',
};

// ── Warnings (no text is sent; the client owns it) ──

String warningCopy(DocWarning w) {
  final d = w.data;
  String v(String k) => d[k] == null ? '—' : '${d[k]}';
  switch (w.code) {
    case 'POS_OVERRIDES_PARTY_STATE':
      return 'Place of supply (${v('pos')}) differs from the customer\'s state (${v('party_state')}).';
    case 'POS_DEFAULTED_TO_TENANT':
      return 'No place of supply given — your own state (${v('pos')}) was used.';
    case 'HSN_DIGITS_MISSING':
      return 'Line ${v('line_no')} needs a ${v('required_digits')}-digit HSN/SAC code.';
    case 'LATE_INVOICE':
      return 'Invoiced late — supplied on ${formatApiDay(d['supply_date'] as String?)}, '
          'invoice dated ${formatApiDay(d['document_date'] as String?)}.';
    case 'DRAFT_CONFIG_USED':
      return 'Some tax rates used are not yet verified by your accountant.';
    case 'LATE_POSTED':
      return 'Posted late — originally dated ${formatApiDay(d['original_date'] as String?)}.';
    case 'QUOTE_RATE_DIFFERS':
      return 'Line ${v('line_no')}: the quote said ${v('quote_rate_pct')}%, '
          'the rate master says ${v('resolved_rate_pct')}%.';
    case 'CASH_LIMIT_WARNING':
      return 'Cash at or above ₹2 lakh from one party in a day — check section 269ST.';
    case 'ITC_CLAIM_SHIFTED':
      return 'Input tax credit moves to a later period.';
    case 'RCM_LIABILITY_SHIFTED':
      return 'Reverse-charge tax is payable by you on this bill.';
    default:
      return _humanise(w.code);
  }
}

// ── Guards (409 structured errors) ──

/// Title + body for a structured accounting error, with the `cause` folded in
/// where it says something the `detail` sentence does not.
({String title, String body}) conflictCopy(AppError e) {
  final c = e.causeMap;
  String cv(String k) => c[k] == null ? '' : '${c[k]}';
  final detail = e.message;
  switch (e.code) {
    case 'ACCOUNTING_NOT_ACTIVE':
      return (title: 'Accounting is not active', body: 'Set it up on the web app first.');
    case 'CUSTOMER_REQUIRED':
      return (title: 'Customer needed', body: 'Pick a customer on the draft before issuing.');
    case 'AMOUNTS_ARE_REQUIRED':
      return (title: 'Tax basis needed', body: 'Choose whether the prices include tax, then issue.');
    case 'HSN_DIGITS_REQUIRED':
      return (
        title: 'HSN/SAC too short',
        body: 'Line ${cv('line_no')} needs ${cv('required_digits')} digits'
            '${cv('hsn_sac').isEmpty ? '' : ' (has ${cv('hsn_sac')})'}. '
            'Lines cannot be edited — void this draft and create it again.',
      );
    case 'TRANSACTION_CLASS_NOT_ALLOWED':
      return (
        title: 'Wrong document type',
        body: '${label(transactionClassLabels, cv('transaction_class'))} supplies need an export invoice.',
      );
    case 'GSTIN_INVALID':
      return (title: 'GSTIN is not valid', body: 'Fix the customer\'s GSTIN in their tax profile.');
    case 'PERIOD_FILED_DATE_IN_OPEN_PERIOD':
      return (
        title: 'Return already filed',
        body: 'GSTR-1 for that period is filed. Use a later date, or raise a credit note instead.',
      );
    case 'RATE_VARIANT_REQUIRED':
      return (
        title: 'Pick a tax rate',
        body: 'HSN/SAC ${cv('hsn_sac')} on line ${cv('line_no')} has more than one rate. '
            'Choose the one that applies — it is saved on the product.',
      );
    case 'RATE_NOT_FOUND':
      return (title: 'No tax rate found', body: detail);
    case 'CONFIG_NOT_VERIFIED':
      return (title: 'Rates not verified', body: 'Ask your accountant to verify the tax configuration.');
    case 'NO_SERIES':
      return (title: 'No numbering series', body: 'Set up invoice numbering on the web app.');
    case 'VOID_NOT_ALLOWED':
      return (title: 'Cannot void', body: 'Only a draft can be voided.');
    case 'CANCEL_NOT_ALLOWED':
      return (title: 'Cannot cancel', body: _cancelReason(cv('reason')));
    case 'NOT_DRAFT':
      return (title: 'Already issued', body: 'Only a draft can be edited.');
    case 'NOTE_NOT_ALLOWED':
      return (title: 'Credit note not allowed', body: _noteReason(cv('reason'), c));
    case 'CN_CUTOFF_PASSED':
      return (
        title: 'Too late for a GST credit note',
        body: 'The cut-off was ${formatApiDay(cv('cutoff'))}. Raise it without GST instead.',
      );
    case 'PARTY_HAS_BOOKS':
      return (title: 'Has accounting history', body: 'It cannot be deleted — deactivate it instead.');
    case 'BANK_ACCOUNT_REQUIRED':
      return (title: 'Pick a bank account', body: 'Bank money needs the account it moved through.');
    case 'GATEWAY_PROVIDER_REQUIRED':
      return (title: 'Gateway needed', body: 'Say which payment gateway collected this.');
    case 'TARGET_NOT_ISSUED':
      return (title: 'Invoice not issued', body: 'Money can only be applied to an issued invoice.');
    case 'AMOUNT_NOT_POSITIVE':
      return (title: 'Amount must be more than zero', body: detail);
    case 'RECEIPT_NOT_POSTED':
    case 'PAYMENT_NOT_POSTED':
      return (title: 'Already reversed', body: 'This has already been reversed.');
    case 'CREDIT_PARTLY_APPLIED':
      return (
        title: 'Credit already used',
        body: 'The credit this receipt created is applied to an invoice. Undo that on the web app first.',
      );
    case 'PAYMENT_EXCEEDS_OPEN_BILLS':
      return (
        title: 'More than what is owed',
        body: 'Vendor payments must match open bills exactly. For a prepayment, record a vendor advance on the web app.',
      );
    case 'NO_OPEN_BILL':
      return (
        title: 'No open bill',
        body: 'This vendor has nothing to pay. For a prepayment, record a vendor advance on the web app.',
      );
    case 'TARGET_BILL_INVALID':
      return (title: 'Bill cannot be paid', body: detail);
    case 'PURCHASE_REJECTED':
      return (title: 'Could not post', body: detail);
    case 'ACCOUNTING_POSTING_REJECTED':
      return (title: 'The ledger refused this', body: _postingReason(cv('code'), c, detail));
    default:
      return (title: 'Could not complete', body: detail);
  }
}

String _cancelReason(String reason) => switch (reason) {
      'NOT_ISSUED' => 'Only an issued document can be cancelled.',
      'HAS_RECEIPT' => 'Money has been received against it. Raise a credit note instead.',
      'PARTIALLY_SETTLED' => 'It is partly settled. Raise a credit note instead.',
      'GSTR1_FILED' => 'It is in a filed GSTR-1. Raise a credit note instead.',
      'IRN_PRESENT' => 'It has an e-invoice IRN.',
      'EWB_PRESENT' => 'It has an e-way bill.',
      'REFERENCED_BY_NOTE' => 'A credit or debit note refers to it.',
      'CREDIT_ALREADY_APPLIED' => 'Its credit has already been applied.',
      _ => 'Check the document\'s state and try again.',
    };

String _noteReason(String reason, Map<String, dynamic> c) => switch (reason) {
      'ORIGINAL_NOT_ISSUED' => 'The original invoice is not issued.',
      'ORIGINAL_LINE_NOT_FOUND' => 'A line no longer matches the original invoice.',
      'EXCEEDS_ORIGINAL' =>
        'It is more than the original (cap ${formatMoneyStr(c['cap'])}).',
      'NO_GST_NOTE_HAS_TAX' => 'A note without GST cannot carry tax.',
      _ => 'Check the lines and amounts, then try again.',
    };

String _postingReason(String code, Map<String, dynamic> c, String detail) => switch (code) {
      'NO_OPEN_BOOK_PERIOD' => 'That month is closed in the books. Use a date in an open month.',
      'IDEMPOTENCY_PAYLOAD_MISMATCH' =>
        'This form was already submitted with different values. Close it and start again.',
      'NO_BANK_ACCOUNT_FOR_METHOD' =>
        'No bank account is set up for "${c['method'] ?? 'this method'}". Pick an account or choose Cash.',
      'ALREADY_REVERSED' => 'It has already been reversed.',
      _ => detail,
    };
