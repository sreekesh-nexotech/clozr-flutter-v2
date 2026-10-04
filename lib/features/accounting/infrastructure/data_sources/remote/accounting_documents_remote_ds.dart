import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../domain/entities/acc_document.dart';
import 'acc_remote_support.dart';
import 'accounting_mappers.dart';

/// Sales documents (`/accounting/documents/…`, handover §8.3). HTTP + mapping
/// only; the repository caches.
///
/// None of the create endpoints take an idempotency key and each creates a new
/// draft per call (§12.1), so callers disable their control after one tap and
/// never retry a timeout blind.
class AccountingDocumentsRemoteDataSource {
  const AccountingDocumentsRemoteDataSource(this._api);

  final ApiService _api;

  /// One raw page. Document rows are heavy (nested lines and tax lines), so
  /// mobile pages at 25 and always sends `doc_type` where it can (§12.4).
  Future<RawPage> fetchPage(Map<String, Object?> filters, {int page = 1, int pageSize = 25}) async {
    final body = await _api.get(ApiEndpoints.accDocuments,
        query: compact({...filters, 'page': page, 'page_size': pageSize}));
    return RawPage.from(body);
  }

  Future<AccDocument?> fetch(String id) async {
    final body = await _api.get(ApiEndpoints.accDocument(id));
    return body is Map ? mapDocument(Map<String, dynamic>.from(body)) : null;
  }

  /// DRAFT only — 409 `NOT_DRAFT` otherwise.
  Future<AccDocument?> patchDraft(String id, Map<String, Object?> fields) async {
    final body = await _api.patch(ApiEndpoints.accDocument(id), body: fields);
    return body is Map ? mapDocument(Map<String, dynamic>.from(body)) : null;
  }

  Future<AccDocument?> createInvoice(Map<String, Object?> body) async {
    final res = await _api.post(ApiEndpoints.accInvoices, body: compact(body));
    return res is Map ? mapDocument(Map<String, dynamic>.from(res)) : null;
  }

  Future<AccDocument?> fromPaymentRecord(String recordId,
      {required String documentDate, String? supplyDate}) async {
    final res = await _api.post(ApiEndpoints.accInvoiceFromRecord,
        body: compact({
          'payment_record': recordId,
          'document_date': documentDate,
          'supply_date': supplyDate,
        }));
    return res is Map ? mapDocument(Map<String, dynamic>.from(res)) : null;
  }

  Future<AccDocument?> fromTicket(String issueId,
      {String? documentDate, String? supplyDate}) async {
    final res = await _api.post(ApiEndpoints.accInvoiceFromTicket,
        body: compact({
          'issue': issueId,
          'document_date': documentDate,
          'supply_date': supplyDate,
        }));
    return res is Map ? mapDocument(Map<String, dynamic>.from(res)) : null;
  }

  Future<TaxPreview> previewTax(String id) async {
    final res = await _api.post(ApiEndpoints.accPreviewTax(id));
    return mapTaxPreview(res is Map ? Map<String, dynamic>.from(res) : const {});
  }

  Future<AccDocument?> issue(String id, {List<Map<String, String>> advanceAdjustments = const []}) async {
    final res = await _api.post(ApiEndpoints.accIssue(id),
        body: {if (advanceAdjustments.isNotEmpty) 'advance_adjustments': advanceAdjustments});
    return res is Map ? mapDocument(Map<String, dynamic>.from(res)) : null;
  }

  Future<AccDocument?> voidDraft(String id) async {
    final res = await _api.post(ApiEndpoints.accVoid(id));
    return res is Map ? mapDocument(Map<String, dynamic>.from(res)) : null;
  }

  Future<AccDocument?> cancel(String id, String reason) async {
    final res = await _api.post(ApiEndpoints.accCancel(id), body: {'reason': reason});
    return res is Map ? mapDocument(Map<String, dynamic>.from(res)) : null;
  }

  Future<InvoicePrint> renderContext(String id) async {
    final res = await _api.get(ApiEndpoints.accRenderContext(id));
    return InvoicePrint(res is Map ? Map<String, dynamic>.from(res) : const {});
  }

  Future<AccDocument?> createCreditNote(Map<String, Object?> body) async {
    final res = await _api.post(ApiEndpoints.accCreditNotes, body: body);
    return res is Map ? mapDocument(Map<String, dynamic>.from(res)) : null;
  }

  /// `GET masters/hsn-rates/` — the variant ladder for one HSN / SAC.
  Future<List<RateVariant>> hsnRates(String hsn, {String? supplyNature, String? onDate}) async {
    final res = await _api.get(ApiEndpoints.accHsnRates,
        query: compact({'hsn': hsn, 'supply_nature': supplyNature, 'on_date': onDate}));
    return mapRateVariants(res is Map ? res['results'] : res);
  }
}
