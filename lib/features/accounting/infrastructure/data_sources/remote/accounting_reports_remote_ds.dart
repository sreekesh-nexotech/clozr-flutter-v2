import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../domain/entities/acc_ledger.dart';
import '../../../domain/entities/acc_periods.dart';
import '../../../domain/entities/acc_reports.dart';
import 'acc_remote_support.dart';
import 'accounting_mappers.dart';

/// Read-only views: reports, the period register and the journal
/// (handover §8.6–8.8).
///
/// Report query parameters are **not validated** server-side — a malformed
/// date is a 500 — so every date here is built by the app as `YYYY-MM-DD` and
/// blanks are dropped before sending (§12.6).
class AccountingReportsRemoteDataSource {
  const AccountingReportsRemoteDataSource(this._api);

  final ApiService _api;

  Map<String, dynamic> _obj(Object? res) => res is Map ? Map<String, dynamic>.from(res) : const {};

  Future<Map<String, dynamic>> arAgingRaw({String? asOf}) async =>
      _obj(await _api.get(ApiEndpoints.accArAging, query: compact({'as_of': asOf})));

  Future<Map<String, dynamic>> apAgingRaw({String? asOf}) async =>
      _obj(await _api.get(ApiEndpoints.accApAging, query: compact({'as_of': asOf})));

  Future<PartyStatement> statement({required bool vendor, required String partyId, String? from, String? to}) async {
    final path = vendor ? ApiEndpoints.accVendorStatement(partyId) : ApiEndpoints.accCustomerStatement(partyId);
    return mapStatement(_obj(await _api.get(path, query: compact({'date_from': from, 'date_to': to}))));
  }

  Future<Map<String, dynamic>> pnlRaw({String? asOf}) async =>
      _obj(await _api.get(ApiEndpoints.accPnl, query: compact({'as_of': asOf})));

  Future<Map<String, dynamic>> balanceSheetRaw({String? asOf}) async =>
      _obj(await _api.get(ApiEndpoints.accBalanceSheet, query: compact({'as_of': asOf})));

  Future<Map<String, dynamic>> trialBalanceRaw({String? asOf}) async =>
      _obj(await _api.get(ApiEndpoints.accTrialBalance, query: compact({'as_of': asOf})));

  Future<GstSummary> gstSummary(String gstPeriodId) async =>
      mapGstSummary(_obj(await _api.get(ApiEndpoints.accGstSummary, query: {'gst_period_id': gstPeriodId})));

  Future<TdsSummary> tdsSummary({String? tdsPeriodId, String? fiscalYearId}) async => mapTdsSummary(_obj(
      await _api.get(ApiEndpoints.accTdsSummary,
          query: compact({'tds_period_id': tdsPeriodId, 'fiscal_year_id': fiscalYearId}))));

  Future<ProjectFinancials?> projectFinancials(String projectId) async =>
      mapProjectFinancials(await _api.get(ApiEndpoints.accProjectFinancials(projectId)));

  // ── Periods ──

  Future<Map<String, dynamic>> periodRegisterRaw({String? fiscalYearId}) async =>
      _obj(await _api.get(ApiEndpoints.accPeriods, query: compact({'fiscal_year_id': fiscalYearId})));

  Future<PeriodChecklist> gstChecklist(String gstPeriodId) async =>
      mapChecklist(_obj(await _api.get(ApiEndpoints.accGstChecklist(gstPeriodId))));

  // ── Journal ──

  /// The journal behind one document — `documents/{id}/journal/` is a 501,
  /// this is the working route (§12.21).
  Future<List<JournalEntry>> entriesForDocument(String documentId) async {
    final res = await _api.get(ApiEndpoints.accJournalEntries, query: {'document': documentId, 'page_size': 50});
    return mapJournalEntries(res is Map ? res['results'] : res);
  }

  Future<JournalEntry?> entry(String id) async {
    final res = await _api.get(ApiEndpoints.accJournalEntry(id));
    return res is Map ? mapJournalEntry(Map<String, dynamic>.from(res)) : null;
  }

  /// Filters by status only — the list ignores document and date filters.
  Future<List<LedgerEvent>> events({String? status}) async {
    final res = await _api.get(ApiEndpoints.accLedgerEvents, query: compact({'status': status, 'page_size': 50}));
    return mapLedgerEvents(res is Map ? res['results'] : res);
  }
}
