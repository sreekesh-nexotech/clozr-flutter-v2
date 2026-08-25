import '../../../../app/config/constants.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/quote.dart';
import '../../domain/entities/view_schema.dart';
import '../../domain/repositories/quotes_repository.dart';
import '../data_sources/local/quotes_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class QuotesRepositoryImpl implements QuotesRepository {
  const QuotesRepositoryImpl(this._local);

  final QuotesMockDataSource _local;

  @override
  Future<List<Quote>> getQuotes() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchQuotes();
  }

  /// Mock mode has no server-side filter, so the seed is narrowed here — the
  /// same result the API returns for `?lead=<lead_id>`.
  @override
  Future<List<Quote>> getQuotesForLead(String leadId) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchQuotes().where((q) => q.leadId == leadId).toList();
  }

  /// Mock mode has no org config, so the form falls back to its built-in
  /// field set — the same contract as an org that has not configured one.
  @override
  Future<ViewSchema> getQuoteSchema() async => ViewSchema.empty;

  /// Mock mode has no org catalog; the drawer falls back to the built-ins.
  @override
  Future<List<CatalogOption>> getQuoteStatuses() async => const [];

  /// No template catalog without a backend; the picker hides itself.
  @override
  Future<List<QuoteTemplate>> getQuoteTemplates() async => const [];

  /// Local echo — mock mode has no backend, so nothing is persisted. Returning
  /// null keeps the caller on the prototype's toast-only path rather than
  /// claiming a quote was created.
  @override
  Future<Quote?> createQuote(Map<String, dynamic> fields) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return null;
  }

  /// Nothing to write to. The screen's optimistic path still runs, so the
  /// prototype behaves as it always did.
  @override
  Future<void> updateQuoteStatus(String quotationId, String statusId) async {
    await Future<void>.delayed(AppConstants.mockLatency);
  }

  /// Mock write: no-op — the seed catalog is immutable here.
  @override
  Future<void> updateQuote(
      String quotationId, Map<String, dynamic> fields) async {}
}
