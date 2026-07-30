import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/quote.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../providers/quotes_providers.dart';

/// Quotes filter — spec-driven drawer wired like the Leads reference (audit §5).
///
/// Generic drawer (title "Quotes"). Status matching uses the *effective* status:
/// a `sent` quote past its validity date evaluates as Expired.

const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// Parse a CRM display date ("15 Jul 2026") to a DateTime; "—"/blank → null.
DateTime? parseQuoteDate(String s) {
  final parts = s.trim().split(RegExp(r'\s+'));
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = _months[parts[1]];
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  return DateTime(year, month, day);
}

/// The effective status of a quote. A quote stored as `sent` whose validity
/// date has passed (relative to [kFilterToday]) counts as `expired` (audit §5).
String quoteEffectiveStatus(Quote q) {
  if (q.status == 'sent') {
    final valid = parseQuoteDate(q.valid);
    if (valid != null && valid.isBefore(kFilterToday)) return 'expired';
  }
  return q.status;
}

/// The company label a quote resolves to (customer wins, else lead).
String? quoteCompany(Quote q) =>
    CrmPartyDirectory.resolve(custId: q.custId, leadId: q.leadId)?.company;

/// Build the Quotes drawer spec from the current quote set.
FilterSpec buildQuotesFilterSpec(List<Quote> quotes) {
  const statusKeys = ['draft', 'sent', 'accepted', 'rejected', 'expired'];
  final statuses = [
    for (final k in statusKeys) FilterOption(id: k, label: StatusMeta$.quote[k]!.label),
  ];
  final ownerIds = quotes.map((q) => q.owner).toSet();
  final owners = [
    for (final u in MockUsers.reps)
      if (ownerIds.contains(u.id)) FilterOption(id: u.id, label: u.name),
  ];
  final companies = (quotes
          .map(quoteCompany)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort())
      .map((c) => FilterOption(id: c, label: c))
      .toList();

  return FilterSpec(
    title: 'Quotes',
    sections: [
      FilterSection(title: 'Status & ownership', fields: [
        FilterField(
            id: 'status',
            label: 'Status',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: statuses),
        FilterField(
            id: 'owner',
            label: 'Owner',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search owner…',
            options: owners),
        FilterField(
            id: 'company',
            label: 'Company',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search company…',
            options: companies),
      ]),
      FilterSection(title: 'Value & dates', fields: [
        const FilterField(
            id: 'value',
            label: 'Quote value',
            control: FilterControl.numberRange,
            unit: '₹ lakhs',
            unitScale: 100000),
        const FilterField(
            id: 'created',
            label: 'Created',
            control: FilterControl.dateRange,
            dateChips: ['today', 'yesterday', 'last7', 'last30', 'last60', 'last90', 'month']),
        const FilterField(
            id: 'validUntil',
            label: 'Valid until',
            control: FilterControl.dateRange,
            dateChips: ['today', 'tomorrow', 'next7', 'next30', 'next60', 'next90']),
      ]),
    ],
  );
}

/// Evaluate a quote against applied filter values.
bool quoteMatchesFilters(Quote q, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('status'), [quoteEffectiveStatus(q)])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('owner'), [q.owner])) return false;
  final company = quoteCompany(q);
  if (!FilterMatch.matchAnyOf(v.choice('company'), company == null ? const [] : [company])) {
    return false;
  }
  if (!FilterMatch.matchRange(v.range('value'), q.amountNum, scale: 100000)) return false;
  if (!FilterMatch.matchDate(v.date('created'), parseQuoteDate(q.issued))) return false;
  if (!FilterMatch.matchDate(v.date('validUntil'), parseQuoteDate(q.valid))) return false;
  return true;
}

// ── Providers ──

/// The Quotes drawer spec, derived from the loaded quotes.
final quotesFilterSpecProvider = Provider<FilterSpec>((ref) {
  final quotes = ref.watch(quotesProvider).valueOrNull ?? const [];
  return buildQuotesFilterSpec(quotes);
});

/// Applied drawer filters for the Quotes list (source of the badge count).
final quoteFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Quotes list (bookmark chips).
final quoteSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
