import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/quote.dart';
import '../../domain/entities/view_schema.dart';
import '../../domain/repositories/quotes_repository.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../../infrastructure/data_sources/local/quotes_mock_ds.dart';
import '../../infrastructure/data_sources/remote/quotes_remote_ds.dart';
import '../../infrastructure/repositories/quotes_api_repository.dart';
import '../../infrastructure/repositories/quotes_repository_impl.dart';
import '../filters/quotes_filter_spec.dart';
import 'crm_party_providers.dart';

/// DI seam: mock-backed without a base URL, API-backed otherwise.
final quotesRepositoryProvider = Provider<QuotesRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const QuotesRepositoryImpl(QuotesMockDataSource());
  }
  return QuotesApiRepository(
    QuotesRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Async source of all quotes.
final quotesProvider = FutureProvider<List<Quote>>(
  (ref) => ref.watch(quotesRepositoryProvider).getQuotes(),
);

/// The quotes raised against one lead — the Quotes tab on the lead detail
/// screen. Keyed by lead id: `GET /quotations/quotations/?lead=<lead_id>`.
final leadQuotesProvider =
    FutureProvider.family<List<Quote>, String>((ref, leadId) {
  if (leadId.isEmpty) return Future.value(const <Quote>[]);
  return ref.watch(quotesRepositoryProvider).getQuotesForLead(leadId);
});

/// The org's Quote layout, driving the New quote form.
///
/// `view_type=detail` — the only schema call that describes the whole form (see
/// [QuotesRemoteDataSource.fetchQuoteSchema]). Fetched once per session, since
/// the layout changes when an admin edits it, not when quotes change.
final quoteSchemaFutureProvider = FutureProvider<ViewSchema>(
  (ref) => ref.watch(quotesRepositoryProvider).getQuoteSchema(),
);

/// Synchronous view of [quoteSchemaFutureProvider] — empty while in flight, so
/// the form renders straight away with its built-in field set and adopts the
/// org's layout when it arrives.
final quoteSchemaProvider = Provider<ViewSchema>(
  (ref) => ref.watch(quoteSchemaFutureProvider).valueOrNull ?? ViewSchema.empty,
);

/// `GET /quotations/templates/` — the org's quote templates.
final quoteTemplatesFutureProvider = FutureProvider<List<QuoteTemplate>>(
  (ref) => ref.watch(quotesRepositoryProvider).getQuoteTemplates(),
);

/// Synchronous view of [quoteTemplatesFutureProvider]; empty means the picker
/// is hidden and the server applies the org default on create.
final quoteTemplatesProvider = Provider<List<QuoteTemplate>>(
  (ref) => ref.watch(quoteTemplatesFutureProvider).valueOrNull ?? const [],
);

/// Look up a single quote by id (detail screen).
final quoteByIdProvider = Provider.family<Quote?, String>((ref, id) {
  final quotes = ref.watch(quotesProvider).valueOrNull;
  if (quotes == null) return null;
  for (final q in quotes) {
    if (q.id == id) return q;
  }
  return null;
});

/// The "Company · Name" one-liner for a quote's linked customer/lead, resolved
/// via [lookup] (real customers in API mode, the seed directory in mock mode).
/// Falls back to the em-dash when the party is unknown.
String quoteWho(Quote q, CrmPartyLookup lookup) =>
    lookup(custId: q.custId, leadId: q.leadId)?.who ?? '—';

// ── List UI state ──
final quoteTabProvider = StateProvider<String>((ref) => 'all');
final quoteSearchProvider = StateProvider<String>((ref) => '');
final quoteSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Quotes filtered by tab + drawer filters + search.
final visibleQuotesProvider = Provider<List<Quote>>((ref) {
  final quotes = ref.watch(quotesProvider).valueOrNull ?? const [];
  final tab = ref.watch(quoteTabProvider);
  final filters = ref.watch(quoteFiltersProvider);
  final q = ref.watch(quoteSearchProvider).trim().toLowerCase();
  final lookup = ref.watch(crmPartyLookupProvider);

  Iterable<Quote> out = quotes;
  if (tab != 'all') out = out.where((x) => x.status == tab);
  if (!filters.isEmpty) out = out.where((x) => quoteMatchesFilters(x, filters));
  if (q.isNotEmpty) {
    out = out.where((x) => ('${x.id} ${quoteWho(x, lookup)}').toLowerCase().contains(q));
  }
  return out.toList();
});

/// Count of quotes for a given tab key.
int quoteTabCount(List<Quote> quotes, String key) {
  if (key == 'all') return quotes.length;
  return quotes.where((q) => q.status == key).length;
}
