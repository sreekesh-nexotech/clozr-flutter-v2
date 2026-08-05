import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/quote.dart';
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
