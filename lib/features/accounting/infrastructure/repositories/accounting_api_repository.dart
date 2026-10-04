import 'dart:convert';

import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/entities/acc_document.dart';
import '../../domain/entities/acc_ledger.dart';
import '../../domain/entities/acc_masters.dart';
import '../../domain/entities/acc_periods.dart';
import '../../domain/entities/acc_reports.dart';
import '../../domain/entities/acc_settlement.dart';
import '../../domain/entities/acc_setup.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../data_sources/remote/acc_remote_support.dart';
import '../data_sources/remote/accounting_documents_remote_ds.dart';
import '../data_sources/remote/accounting_mappers.dart';
import '../data_sources/remote/accounting_masters_remote_ds.dart';
import '../data_sources/remote/accounting_reports_remote_ds.dart';
import '../data_sources/remote/accounting_settlement_remote_ds.dart';

/// API-backed [AccountingRepository].
///
/// Reads go to the server; the list reads that make sense offline (first
/// document page per filter, vendors, settlement lists, the period register
/// and today's reports) are cached raw in Hive and served back on a network or
/// timeout failure. Writes are remote only and drop the read caches they could
/// have made stale — the plan's rule of never queueing a post applies here:
/// nothing is written to the cache on the way out.
class AccountingApiRepository implements AccountingRepository {
  AccountingApiRepository({
    required this.documentsDs,
    required this.mastersDs,
    required this.settlementDs,
    required this.reportsDs,
  });

  final AccountingDocumentsRemoteDataSource documentsDs;
  final AccountingMastersRemoteDataSource mastersDs;
  final AccountingSettlementRemoteDataSource settlementDs;
  final AccountingReportsRemoteDataSource reportsDs;

  static const _box = AppCache.accountingCache;

  /// Remote first; on a network/timeout failure the cached copy, if any.
  Future<T> _cached<T>(String key, Future<Object> Function() fetch, T Function(Object data) map) async {
    try {
      final data = await fetch();
      await AppCache.put(_box, key, data);
      return map(data);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(_box, key)?.data;
        if (cached != null) return map(cached);
      }
      rethrow;
    }
  }

  /// Drops every cached read. Called after any write: the set of reads one
  /// posting can move (documents, balances, aging, the register) is most of
  /// them, and a stale ledger figure is worse than one refetch.
  Future<void> _invalidate() => AppCache.clearBox(_box);

  String _key(String name, [Map<String, Object?> params = const {}]) =>
      params.isEmpty ? name : '$name:${jsonEncode(compact(params))}';

  // ── Status ──

  @override
  Future<Set<String>> myFeatures() => mastersDs.myFeatures();

  @override
  Future<TenantProfile?> tenantProfile() => mastersDs.tenantProfile();

  @override
  Future<bool> probeActive(String path) => mastersDs.probeActive(path);

  @override
  Future<List<TenantAttribute>> tenantAttributes() => mastersDs.tenantAttributes();

  @override
  Future<GatesReport?> gates() => mastersDs.gates();

  @override
  Future<List<GstState>> states() => _cached(
        _key('states'),
        () async => [
          for (final s in await mastersDs.states()) {'code': s.code, 'name': s.name, 'alpha': s.alpha},
        ],
        mapStates,
      );

  // ── Documents ──

  @override
  Future<AccDocumentPage> documents(Map<String, Object?> filters, {int page = 1}) async {
    AccDocumentPage toPage(RawPage p) =>
        AccDocumentPage(results: mapDocuments(p.rows), count: p.count, hasMore: p.hasMore);
    // Only the first page is cached — it is what an offline open shows.
    if (page != 1) return toPage(await documentsDs.fetchPage(filters, page: page));
    return _cached(
      _key('docs', filters),
      () async => (await documentsDs.fetchPage(filters)).toJson(),
      (data) => toPage(RawPage.fromCache(data)),
    );
  }

  @override
  Future<AccDocument?> document(String id) => documentsDs.fetch(id);

  Future<T> _write<T>(Future<T> Function() call) async {
    final out = await call();
    await _invalidate();
    return out;
  }

  @override
  Future<AccDocument?> patchDraft(String id, Map<String, Object?> fields) =>
      _write(() => documentsDs.patchDraft(id, fields));

  @override
  Future<AccDocument?> createInvoice(Map<String, Object?> body) => _write(() => documentsDs.createInvoice(body));

  @override
  Future<AccDocument?> invoiceFromPaymentRecord(String recordId, {required String documentDate, String? supplyDate}) =>
      _write(() => documentsDs.fromPaymentRecord(recordId, documentDate: documentDate, supplyDate: supplyDate));

  @override
  Future<AccDocument?> invoiceFromTicket(String issueId, {String? documentDate}) =>
      _write(() => documentsDs.fromTicket(issueId, documentDate: documentDate));

  @override
  Future<TaxPreview> previewTax(String id) => documentsDs.previewTax(id);

  @override
  Future<AccDocument?> issue(String id, {List<Map<String, String>> advanceAdjustments = const []}) =>
      _write(() => documentsDs.issue(id, advanceAdjustments: advanceAdjustments));

  @override
  Future<AccDocument?> voidDraft(String id) => _write(() => documentsDs.voidDraft(id));

  @override
  Future<AccDocument?> cancel(String id, String reason) => _write(() => documentsDs.cancel(id, reason));

  @override
  Future<InvoicePrint> renderContext(String id) => documentsDs.renderContext(id);

  @override
  Future<AccDocument?> createCreditNote(Map<String, Object?> body) =>
      _write(() => documentsDs.createCreditNote(body));

  @override
  Future<List<RateVariant>> hsnRates(String hsn, {String? supplyNature}) =>
      documentsDs.hsnRates(hsn, supplyNature: supplyNature, onDate: isoDay(DateTime.now()));

  // ── Masters ──

  @override
  Future<List<Vendor>> vendors({String? search, bool? active}) {
    // Every page, up to a sane cap: pickers and the name lookup on document
    // rows both need the whole list, and one page of 200 silently cut the rest
    // off — their rows then showed "Vendor" instead of a name.
    Future<RawPage> fetch() async {
      final rows = <Map<String, dynamic>>[];
      var page = 1;
      var more = true;
      while (more && page <= 10) {
        final p = await mastersDs.fetchVendorPage(search: search, active: active, page: page, pageSize: 200);
        rows.addAll(p.rows);
        more = p.hasMore;
        page++;
      }
      return RawPage(rows, count: rows.length);
    }

    // A search is not the list; only the unfiltered read is cached.
    if ((search ?? '').isNotEmpty) return fetch().then((p) => mapVendors(p.rows));
    return _cached(
      _key('vendors', {'active': active}),
      () async => (await fetch()).toJson(),
      (data) => mapVendors(RawPage.fromCache(data).rows),
    );
  }

  @override
  Future<Vendor?> vendor(String id) => mastersDs.fetchVendor(id);

  @override
  Future<Vendor?> createVendor(Map<String, Object?> fields) => _write(() => mastersDs.createVendor(fields));

  @override
  Future<Vendor?> updateVendor(String id, Map<String, Object?> fields) =>
      _write(() => mastersDs.updateVendor(id, fields));

  @override
  Future<void> deleteVendor(String id) => _write(() => mastersDs.deleteVendor(id));

  @override
  Future<PartyTaxProfile> partyTaxProfile(String kind, String id) => mastersDs.partyTaxProfile(kind, id);

  @override
  Future<PartyTaxProfile> savePartyTaxProfile(String kind, String id, Map<String, Object?> body) =>
      _write(() => mastersDs.savePartyTaxProfile(kind, id, body));

  @override
  Future<Map<String, bool>> customerB2bFlags(List<String> ids) => mastersDs.customerB2bFlags(ids);

  @override
  Future<ProductTaxProfile> productTaxProfile(String productId) => mastersDs.productTaxProfile(productId);

  @override
  Future<ProductTaxProfile> saveProductTaxProfile(String productId, Map<String, Object?> body) =>
      _write(() => mastersDs.saveProductTaxProfile(productId, body));

  @override
  Future<List<BankAccount>> bankAccounts() => mastersDs.bankAccounts();

  // ── Settlement & purchases ──

  Future<List<T>> _list<T>(String name, Map<String, Object?> params, Future<RawPage> Function() fetch,
          List<T> Function(Object? rows) map) =>
      _cached(_key(name, params), () async => (await fetch()).toJson(),
          (data) => map(RawPage.fromCache(data).rows));

  @override
  Future<List<AccReceipt>> receipts({String? customer, String? status}) => _list(
      'receipts', {'c': customer, 's': status},
      () => settlementDs.fetchReceipts(customer: customer, status: status), mapReceipts);

  @override
  Future<AccReceipt?> receipt(String id) => settlementDs.fetchReceipt(id);

  @override
  Future<PostOutcome<AccReceipt>> recordReceipt(Map<String, Object?> body) =>
      _write(() => settlementDs.recordReceipt(body));

  @override
  Future<PostOutcome<String>> reverseReceipt(String id, {String? reason, required String eventId}) =>
      _write(() => settlementDs.reverseReceipt(id, reason: reason, eventId: eventId));

  @override
  Future<List<AccAdvance>> advances({String? customer, String? status}) => _list(
      'advances', {'c': customer, 's': status},
      () => settlementDs.fetchAdvances(customer: customer, status: status), mapAdvances);

  @override
  Future<PostOutcome<AccReceipt>> recordAdvance(Map<String, Object?> body) =>
      _write(() => settlementDs.recordAdvance(body));

  @override
  Future<List<AccCustomerCredit>> customerCredits({String? customer, String? status}) => _list(
      'credits', {'c': customer, 's': status},
      () => settlementDs.fetchCustomerCredits(customer: customer, status: status), mapCustomerCredits);

  @override
  Future<List<AccVendorPayment>> vendorPayments({String? vendor, String? status}) => _list(
      'vpayments', {'v': vendor, 's': status},
      () => settlementDs.fetchVendorPayments(vendor: vendor, status: status), mapVendorPayments);

  @override
  Future<AccVendorPayment?> vendorPayment(String id) => settlementDs.fetchVendorPayment(id);

  @override
  Future<PostOutcome<AccVendorPayment>> recordVendorPayment(Map<String, Object?> body) =>
      _write(() => settlementDs.recordVendorPayment(body));

  @override
  Future<PostOutcome<String>> reverseVendorPayment(String id, {required String eventId}) =>
      _write(() => settlementDs.reverseVendorPayment(id, eventId: eventId));

  @override
  Future<List<AccVendorAdvance>> vendorAdvances({String? vendor}) => _list(
      'vadvances', {'v': vendor}, () => settlementDs.fetchVendorAdvances(vendor: vendor), mapVendorAdvances);

  @override
  Future<PostOutcome<AccDocument>> recordVendorBill(Map<String, Object?> body) =>
      _write(() => settlementDs.recordVendorBill(body));

  @override
  Future<PostOutcome<AccDocument>> recordExpense(Map<String, Object?> body) =>
      _write(() => settlementDs.recordExpense(body));

  // ── Journal, periods, reports ──

  @override
  Future<List<JournalEntry>> journalForDocument(String documentId) => reportsDs.entriesForDocument(documentId);

  @override
  Future<JournalEntry?> journalEntry(String id) => reportsDs.entry(id);

  @override
  Future<List<LedgerEvent>> ledgerEvents({String? status}) => reportsDs.events(status: status);

  @override
  Future<PeriodRegister> periodRegister() => _cached(
      _key('periods'), () => reportsDs.periodRegisterRaw(), (d) => mapPeriodRegister(_asMap(d)));

  @override
  Future<PeriodChecklist> gstChecklist(String gstPeriodId) => reportsDs.gstChecklist(gstPeriodId);

  @override
  Future<AgingReport> aging({required bool payable}) {
    final asOf = isoDay(DateTime.now());
    return _cached(
      _key(payable ? 'ap_aging' : 'ar_aging', {'as_of': asOf}),
      () => payable ? reportsDs.apAgingRaw(asOf: asOf) : reportsDs.arAgingRaw(asOf: asOf),
      (d) => mapAging(_asMap(d), vendor: payable),
    );
  }

  @override
  Future<PartyStatement> statement({required bool vendor, required String partyId, String? from, String? to}) =>
      reportsDs.statement(vendor: vendor, partyId: partyId, from: from, to: to);

  @override
  Future<PnlReport> pnl({String? asOf}) => _cached(
      _key('pnl', {'as_of': asOf}), () => reportsDs.pnlRaw(asOf: asOf), (d) => mapPnl(_asMap(d)));

  @override
  Future<BalanceSheetReport> balanceSheet({String? asOf}) => _cached(_key('bs', {'as_of': asOf}),
      () => reportsDs.balanceSheetRaw(asOf: asOf), (d) => mapBalanceSheet(_asMap(d)));

  @override
  Future<TrialBalanceReport> trialBalance({String? asOf}) => _cached(_key('tb', {'as_of': asOf}),
      () => reportsDs.trialBalanceRaw(asOf: asOf), (d) => mapTrialBalance(_asMap(d)));

  @override
  Future<GstSummary> gstSummary(String gstPeriodId) => reportsDs.gstSummary(gstPeriodId);

  @override
  Future<TdsSummary> tdsSummary({String? tdsPeriodId}) => reportsDs.tdsSummary(tdsPeriodId: tdsPeriodId);

  @override
  Future<ProjectFinancials?> projectFinancials(String projectId) => reportsDs.projectFinancials(projectId);

  static Map<String, dynamic> _asMap(Object? d) => d is Map ? Map<String, dynamic>.from(d) : const {};
}
