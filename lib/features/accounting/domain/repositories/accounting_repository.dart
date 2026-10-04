import '../entities/acc_document.dart';
import '../entities/acc_ledger.dart';
import '../entities/acc_masters.dart';
import '../entities/acc_periods.dart';
import '../entities/acc_reports.dart';
import '../entities/acc_settlement.dart';
import '../entities/acc_setup.dart';

/// Everything the mobile accounting screens read and write.
///
/// One facade rather than one repository per backend app: the screens cut
/// across areas (a document detail reads documents, journal and settlement),
/// and every method is a thin pass-through with read caching on top.
///
/// There is no mock implementation. Accounting has no prototype seed, and in
/// mock mode the status resolves to [AccountingStatus.unavailable] before any
/// screen could call this — inventing ledger figures for a demo build would be
/// exactly the fabricated-looking data the app avoids.
abstract class AccountingRepository {
  // Status pre-checks (handover §2)
  Future<Set<String>> myFeatures();
  Future<TenantProfile?> tenantProfile();
  Future<bool> probeActive(String path);
  Future<List<TenantAttribute>> tenantAttributes();
  Future<GatesReport?> gates();
  Future<List<GstState>> states();

  // Documents
  Future<AccDocumentPage> documents(Map<String, Object?> filters, {int page = 1});
  Future<AccDocument?> document(String id);
  Future<AccDocument?> patchDraft(String id, Map<String, Object?> fields);
  Future<AccDocument?> createInvoice(Map<String, Object?> body);
  Future<AccDocument?> invoiceFromPaymentRecord(String recordId, {required String documentDate, String? supplyDate});
  Future<AccDocument?> invoiceFromTicket(String issueId, {String? documentDate});
  Future<TaxPreview> previewTax(String id);
  Future<AccDocument?> issue(String id, {List<Map<String, String>> advanceAdjustments});
  Future<AccDocument?> voidDraft(String id);
  Future<AccDocument?> cancel(String id, String reason);
  Future<InvoicePrint> renderContext(String id);
  Future<AccDocument?> createCreditNote(Map<String, Object?> body);
  Future<List<RateVariant>> hsnRates(String hsn, {String? supplyNature});

  // Masters
  Future<List<Vendor>> vendors({String? search, bool? active});
  Future<Vendor?> vendor(String id);
  Future<Vendor?> createVendor(Map<String, Object?> fields);
  Future<Vendor?> updateVendor(String id, Map<String, Object?> fields);
  Future<void> deleteVendor(String id);
  Future<PartyTaxProfile> partyTaxProfile(String kind, String id);
  Future<PartyTaxProfile> savePartyTaxProfile(String kind, String id, Map<String, Object?> body);
  Future<Map<String, bool>> customerB2bFlags(List<String> ids);
  Future<ProductTaxProfile> productTaxProfile(String productId);
  Future<ProductTaxProfile> saveProductTaxProfile(String productId, Map<String, Object?> body);
  Future<List<BankAccount>> bankAccounts();

  // Settlement & purchases
  Future<List<AccReceipt>> receipts({String? customer, String? status});
  Future<AccReceipt?> receipt(String id);
  Future<PostOutcome<AccReceipt>> recordReceipt(Map<String, Object?> body);
  Future<PostOutcome<String>> reverseReceipt(String id, {String? reason, required String eventId});
  Future<List<AccAdvance>> advances({String? customer, String? status});
  Future<PostOutcome<AccReceipt>> recordAdvance(Map<String, Object?> body);
  Future<List<AccCustomerCredit>> customerCredits({String? customer, String? status});
  Future<List<AccVendorPayment>> vendorPayments({String? vendor, String? status});
  Future<AccVendorPayment?> vendorPayment(String id);
  Future<PostOutcome<AccVendorPayment>> recordVendorPayment(Map<String, Object?> body);
  Future<PostOutcome<String>> reverseVendorPayment(String id, {required String eventId});
  Future<List<AccVendorAdvance>> vendorAdvances({String? vendor});
  Future<PostOutcome<AccDocument>> recordVendorBill(Map<String, Object?> body);
  Future<PostOutcome<AccDocument>> recordExpense(Map<String, Object?> body);

  // Journal, periods, reports (read-only)
  Future<List<JournalEntry>> journalForDocument(String documentId);
  Future<JournalEntry?> journalEntry(String id);
  Future<List<LedgerEvent>> ledgerEvents({String? status});
  Future<PeriodRegister> periodRegister();
  Future<PeriodChecklist> gstChecklist(String gstPeriodId);
  Future<AgingReport> aging({required bool payable});
  Future<PartyStatement> statement({required bool vendor, required String partyId, String? from, String? to});
  Future<PnlReport> pnl({String? asOf});
  Future<BalanceSheetReport> balanceSheet({String? asOf});
  Future<TrialBalanceReport> trialBalance({String? asOf});
  Future<GstSummary> gstSummary(String gstPeriodId);
  Future<TdsSummary> tdsSummary({String? tdsPeriodId});
  Future<ProjectFinancials?> projectFinancials(String projectId);
}
