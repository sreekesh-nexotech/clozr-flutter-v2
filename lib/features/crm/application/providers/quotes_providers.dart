import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/crm_catalog.dart';
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

/// `GET /quotations/statuses/` — the org's own quote statuses, for the drawer.
final quoteStatusCatalogProvider = FutureProvider<List<CatalogOption>>(
  (ref) => ref.watch(quotesRepositoryProvider).getQuoteStatuses(),
);

/// Synchronous view — empty while in flight, in mock mode and on failure, which
/// the drawer reads as "use the built-in status vocabulary".
final quoteStatusOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(quoteStatusCatalogProvider).valueOrNull ?? const [],
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

/// The headline a quote should carry: who it is for, and failing that what it
/// is called.
///
/// [quoteWho] alone was not enough. The list serializer trims each row to the
/// org's visible columns, so an org that hides `lead` and `customer` — as the
/// seeded mobile layout does — sends no party to resolve, and every card fell
/// back to the em dash while the org's own `quotation_title` sat unused in the
/// payload. The party still wins where there is one, so a layout that exposes
/// it reads exactly as before.
String quoteHeadline(Quote q, CrmPartyLookup lookup) {
  final who = lookup(custId: q.custId, leadId: q.leadId)?.who;
  if (who != null && who.trim().isNotEmpty) return who;
  final title = q.title?.trim();
  return (title == null || title.isEmpty) ? '—' : title;
}

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
  // The same tab set the chips are built from, so the rows a tab lists are
  // exactly the rows its count promised.
  final tabKeys = ref.watch(quoteTabKeysProvider);
  if (tab != 'all') out = out.where((x) => quoteInTab(x, tab, tabKeys: tabKeys));
  if (!filters.isEmpty) out = out.where((x) => quoteMatchesFilters(x, filters, lookup));
  if (q.isNotEmpty) {
    // Searches the title too — it is what the card shows whenever the org's
    // layout hides the party, so searching for it has to find the row.
    out = out.where((x) =>
        ('${x.id} ${quoteWho(x, lookup)} ${x.title ?? ''}').toLowerCase().contains(q));
  }
  return out.toList();
});

/// Whether a quote belongs under a status tab — **one tab per quote**, so the
/// chip counts add up to the All count.
///
/// The tab key is the org's own status name once `/quotations/statuses/` has
/// loaded ("Sent", "Under Review"), and a built-in folded key ("draft",
/// "expired") before it does or in mock mode.
///
/// The org's name is the authority whenever the API sent one: it is what the
/// card's pill shows ([quoteStatusMeta]), so it is where the row must be
/// counted. The folded key is a **fallback**, used only when the row has no
/// status name or when the name is not one the tab row offers — a status the
/// org removed, or any name at all during the window before the catalog loads.
///
/// [tabKeys] is the set of keys the tab row is showing (lower-cased, without
/// `all`). Without it the fallback cannot tell "this row has a tab of its own"
/// from "it does not", and the two clauses go back to overlapping: that is the
/// bug this replaced — a sent quote past its validity date folds to `expired`,
/// matched both the Sent tab (by name) and the Expired tab (by folded key), and
/// was counted twice.
bool quoteInTab(Quote q, String tabKey, {Set<String> tabKeys = const {}}) {
  final tab = tabKey.trim().toLowerCase();
  if (tab == 'all') return true;

  final name = q.statusName.trim().toLowerCase();
  if (name.isEmpty) return q.status == tab;
  if (name == tab) return true;
  // The row's own status has a chip of its own, so this is not its tab.
  if (tabKeys.contains(name)) return false;
  return q.status == tab;
}

/// Count of quotes for a given tab key. See [quoteInTab] for [tabKeys].
int quoteTabCount(List<Quote> quotes, String key,
    {Set<String> tabKeys = const {}}) {
  if (key == 'all') return quotes.length;
  return quotes.where((q) => quoteInTab(q, key, tabKeys: tabKeys)).length;
}

/// The keys the status tab row is showing, lower-cased and without `all`.
///
/// Mirrors how the screen builds its chips — the org's own statuses once the
/// catalog has loaded, the built-in five before it does — so counting and
/// rendering can never disagree about which tabs exist.
final quoteTabKeysProvider = Provider<Set<String>>((ref) {
  final statuses = ref.watch(quoteStatusOptionsProvider);
  if (statuses.isEmpty) {
    return const {'draft', 'sent', 'accepted', 'rejected', 'expired'};
  }
  return {for (final s in statuses) s.name.trim().toLowerCase()};
});
