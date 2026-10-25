import 'package:intl/intl.dart';

// Pure rules of the "Record payment" sheet, mirroring the webapp's
// `RecordPaymentModal` + `payments.repository.impl.ts#recordPayment`. Nothing
// here touches Flutter or the network, so every rule is unit-tested.

/// The two ways to record money against a plan.
enum RecordMode { settle, adhoc }

/// One payment method: the label shown and the API `payment_method` code.
typedef PayMethod = ({String label, String code});

/// Webapp `PAYMENT_METHOD_OPTS`, in order — Bank transfer is the default.
const List<PayMethod> recordPayMethods = [
  (label: 'Bank transfer', code: 'bank_transfer'),
  (label: 'UPI', code: 'upi'),
  (label: 'Card', code: 'card'),
  (label: 'Cash', code: 'cash'),
  (label: 'Cheque', code: 'cheque'),
  (label: 'Auto-debit', code: 'auto_debit'),
];

const String defaultPayMethodCode = 'bank_transfer';

/// Webapp `adhocAllowedFor`: ad-hoc records exist only on milestone plans.
bool adhocAllowedFor(String? paymentType) => paymentType == 'installment_custom';

const String adhocUnavailableCopy = 'Ad-hoc amounts are only available on milestone-based plans';

/// The mode actually in force: any non-milestone plan is always "settle",
/// whatever tab was chosen before the plan was picked.
RecordMode effectiveMode(RecordMode chosen, String? paymentType) =>
    adhocAllowedFor(paymentType) ? chosen : RecordMode.settle;

/// The banner shown when nothing is left to settle.
String allSettledCopy(String? paymentType) => adhocAllowedFor(paymentType)
    ? 'All installments on this plan are settled. Switch to Ad-hoc to log an extra payment.'
    : 'All installments on this plan are settled.';

// ── Money ──

/// Webapp `money`: `₹10,000`, `₹3,932.50` (paise only when there are some),
/// `-₹250`.
String rupees(num value) {
  final n = (value * 100).round() / 100;
  final whole = (n * 100).round() % 100 == 0;
  final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: whole ? 0 : 2);
  return n < 0 ? '-${f.format(-n)}' : f.format(n);
}

/// A money string/number from the API → double (0 when absent or garbage).
double apiMoney(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '').trim()) ?? 0;
  return 0;
}

/// A deduction box (TDS / bank charge) → rupees. Blank, garbage or negative
/// → 0, as on the web (`toMoney`).
double deductionInput(String raw) {
  final v = double.tryParse(raw.replaceAll(',', '').trim());
  return v != null && v.isFinite && v > 0 ? v : 0;
}

/// Webapp `amountInput`: seed the amount box from a balance — paise only when
/// present, blank for nothing.
String amountSeed(double n) {
  final r = (n * 100).round() / 100;
  if (r <= 0) return '';
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2);
}

/// A rupee figure as the API's decimal string.
String wireMoney(double v) => ((v * 100).round() / 100).toStringAsFixed(2);

/// What is open on an instalment: the server's gross `balance_due` (incl. GST),
/// falling back to the gross due itself (webapp).
double openBalance({required double balanceDue, required double amountDueGross}) =>
    balanceDue > 0 ? balanceDue : amountDueGross;

/// "Settles as cash received + ₹1,000 TDS + ₹50 bank charge." — null when
/// there are no deductions.
String? deductionsNote(double tds, double bankCharge) {
  if (tds <= 0 && bankCharge <= 0) return null;
  return 'Settles as cash received + ${rupees(tds)} TDS + ${rupees(bankCharge)} bank charge.';
}

// ── Validation ──

/// The settle-mode amount check. Either [error] or [amountPaid] (the cash
/// figure sent: the amount received net of TDS and bank charge).
class SettleAmount {
  const SettleAmount._({this.error, this.owed = 0, this.amountPaid = 0});
  final String? error;

  /// What the instalment is credited with (cash + deductions).
  final double owed;

  /// The cash actually received — `amount_paid` on the wire.
  final double amountPaid;
  bool get ok => error == null;
}

/// Webapp settle rules: an empty box means the full open balance; 0 or
/// negative is invalid; more than the open balance is refused; deductions must
/// leave some cash.
SettleAmount validateSettleAmount({
  required String raw,
  required double balance,
  double tds = 0,
  double bankCharge = 0,
}) {
  final text = raw.replaceAll(',', '').trim();
  final double owed;
  if (text.isEmpty) {
    owed = balance;
  } else {
    final v = double.tryParse(text);
    if (v == null || !v.isFinite || v <= 0) return const SettleAmount._(error: 'Enter a valid amount');
    owed = v;
  }
  if (owed <= 0) return const SettleAmount._(error: 'Enter a valid amount');
  if (owed > balance + 0.005) {
    return SettleAmount._(error: 'Amount cannot exceed the open balance of ${rupees(balance)}');
  }
  final deductions = tds + bankCharge;
  if (deductions >= owed) return const SettleAmount._(error: 'Deductions cannot cover the whole installment');
  return SettleAmount._(owed: owed, amountPaid: ((owed - deductions) * 100).round() / 100);
}

/// The ad-hoc amount check: a positive amount, not wholly eaten by deductions.
String? validateAdhocAmount(String raw, {double tds = 0, double bankCharge = 0}) {
  final v = double.tryParse(raw.replaceAll(',', '').trim());
  if (raw.trim().isEmpty || v == null || !v.isFinite || v <= 0) return 'Enter a valid amount';
  if (tds + bankCharge >= v) return 'Deductions cannot cover the whole amount';
  return null;
}

/// Webapp `paymentDateError`: the money cannot have arrived after today.
String? paymentDateError(DateTime date, DateTime today) {
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(today.year, today.month, today.day);
  return d.isAfter(t) ? 'The payment date cannot be in the future.' : null;
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ── Request bodies ──

/// Optional settlement details (webapp `SettlementDetails`). Only non-empty
/// keys reach the wire.
class SettlementDetails {
  const SettlementDetails({
    this.tds = 0,
    this.bankCharge = 0,
    this.gatewayRef = '',
    this.bankAccountId,
    this.treatAs,
  });

  final double tds;
  final double bankCharge;
  final String gatewayRef;
  final String? bankAccountId;
  final String? treatAs;

  double get deductions => tds + bankCharge;

  /// Webapp `toSettlementBody`. TDS / bank charge are accepted only on a
  /// record being marked `paid`, so [willBePaid] gates them.
  Map<String, dynamic> toBody({required bool willBePaid}) => {
        if (willBePaid && tds > 0) 'tds_deducted': wireMoney(tds),
        if (willBePaid && bankCharge > 0) 'bank_charge': wireMoney(bankCharge),
        if (gatewayRef.trim().isNotEmpty) 'gateway_ref': gatewayRef.trim(),
        if (bankAccountId != null && bankAccountId!.isNotEmpty) 'bank_account_id': bankAccountId,
        if (treatAs != null && treatAs!.isNotEmpty) 'treat_as': treatAs,
      };
}

/// `PATCH /quotations/payment-records/{id}/` — settle an instalment. Always
/// `status: paid`; the server keeps the record pending (settlement "Partly
/// paid") until cash + TDS + bank charge cover its gross balance.
Map<String, dynamic> buildSettleBody({
  required double amountPaid,
  required DateTime paidDate,
  required String method,
  SettlementDetails details = const SettlementDetails(),
}) =>
    {
      'status': 'paid',
      'amount_paid': wireMoney(amountPaid),
      'paid_date': isoDate(paidDate),
      'payment_method': method,
      ...details.toBody(willBePaid: true),
    };

/// `POST /quotations/payment-records/` — an ad-hoc record on a milestone
/// plan. Paid when the cash plus deductions cover the amount.
Map<String, dynamic> buildAdhocBody({
  required String planId,
  required double amount,
  required DateTime paidDate,
  required String method,
  String label = '',
  SettlementDetails details = const SettlementDetails(),
}) {
  final amountPaid = amount - details.deductions;
  final status = amountPaid + details.deductions >= amount ? 'paid' : 'pending';
  return {
    'payment': planId,
    'amount_expected': wireMoney(amount),
    'amount_paid': wireMoney(amountPaid),
    'status': status,
    'paid_date': isoDate(paidDate),
    'payment_method': method,
    if (label.trim().isNotEmpty) 'notes': label.trim(),
    ...details.toBody(willBePaid: status == 'paid'),
  };
}

// ── Lead conversion before recording (webapp round 4 Q4) ──

const String convertLeadPromptCopy =
    'Convert this quote’s lead to a customer (the same as the Convert button) and the payment is recorded right after.';
const String conversionSentForApprovalCopy =
    'Conversion sent for approval. Record the payment once an approver has converted the lead.';
const String conversionAlreadyPendingCopy =
    'A conversion request for this lead is already waiting for approval. Record the payment once it is approved.';
const String noWonStatusCopy = 'This organisation has no Won status to move the lead to.';

String markWonPromptCopy(String wonName) =>
    'This lead isn’t Won yet. Recording a payment will mark it $wonName and convert it to a customer.';

String leadConvertedToast(String? customerName) => (customerName ?? '').trim().isNotEmpty
    ? 'Lead converted — customer ${customerName!.trim()} created'
    : 'Lead converted to a customer';

/// Webapp `isCustomerRequiredFailure`.
bool isCustomerRequiredFailure({String? code, String? message}) {
  if (code == 'CUSTOMER_REQUIRED') return true;
  return (message ?? '').toLowerCase().contains('convert the lead to a customer');
}

/// A plan whose quote belongs to a lead with no customer yet must convert it
/// before money is recorded against it.
bool planNeedsCustomer({required bool hasCustomer, required String quotationUuid}) =>
    !hasCustomer && quotationUuid.isNotEmpty;

/// Where the lead behind a quote stands (webapp `QuoteLeadConversion`).
class QuoteLeadState {
  const QuoteLeadState({
    required this.leadId,
    required this.isWon,
    required this.isConverted,
    required this.pending,
    this.wonStatusId,
    this.wonStatusName,
  });

  final String leadId;
  final bool isWon;
  final bool isConverted;
  final bool pending;
  final String? wonStatusId;
  final String? wonStatusName;
}

/// What "Convert lead and continue" does next.
enum ConvertStep {
  /// Already a customer: just record.
  recordNow,

  /// A conversion request already waits for approval.
  alreadyPending,

  /// Not Won and the org has no Won status.
  noWonStatus,

  /// Not Won: ask before moving it to Won.
  confirmMarkWon,

  /// Won: convert now.
  convert,
}

/// Webapp `convertAndContinue` decision.
ConvertStep convertStepFor(QuoteLeadState s) {
  if (s.isConverted) return ConvertStep.recordNow;
  if (s.pending) return ConvertStep.alreadyPending;
  if (!s.isWon) return s.wonStatusId == null ? ConvertStep.noWonStatus : ConvertStep.confirmMarkWon;
  return ConvertStep.convert;
}

/// Webapp `pickWonStatus`: the type's pick among Won statuses, else the first.
({String id, String name})? pickWonStatus(List<Map<String, dynamic>> statuses) {
  final won = [
    for (final s in statuses)
      if (s['is_won'] == true && s['is_active'] != false) s,
  ];
  if (won.isEmpty) return null;
  final pick = won.firstWhere((s) => s['is_type_pick'] == true, orElse: () => won.first);
  final id = '${pick['lead_status_id'] ?? pick['id'] ?? ''}';
  return id.isEmpty ? null : (id: id, name: '${pick['name'] ?? 'Won'}');
}

/// Reads [QuoteLeadState] from a lead record (`GET /crm/leads/{id}/`) and the
/// org's statuses — "Won" by the record's `status_type`, else by the status
/// whose name matches.
QuoteLeadState quoteLeadStateFrom(String leadId, Map<String, dynamic> lead, List<Map<String, dynamic>> statuses) {
  final values = lead['values'] is Map ? Map<String, dynamic>.from(lead['values'] as Map) : lead;
  final statusName = values['status'] is Map ? (values['status'] as Map)['name'] : values['status'];
  final current = statuses.where((s) => s['name'] == statusName).firstOrNull;
  final won = pickWonStatus(statuses);
  return QuoteLeadState(
    leadId: leadId,
    isWon: values['status_type'] == 'won' || current?['is_won'] == true,
    isConverted: values['is_converted'] == true,
    pending: values['pending_conversion'] is Map,
    wonStatusId: won?.id,
    wonStatusName: won?.name,
  );
}
