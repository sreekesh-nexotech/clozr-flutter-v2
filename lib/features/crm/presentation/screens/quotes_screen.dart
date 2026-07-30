import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/quotes_filter_spec.dart';
import '../../application/providers/quotes_providers.dart';
import '../components/quote_card.dart';
import '../components/saved_chip_row.dart';

/// Quotes list — status-tab list of quote cards over the standard list header,
/// wired to the spec-driven filter engine (drawer → matcher → badge → saved
/// views), mirroring the Leads reference.
class QuotesScreen extends ConsumerStatefulWidget {
  const QuotesScreen({super.key});

  @override
  ConsumerState<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends ConsumerState<QuotesScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(quoteSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Add quote form on this screen.
    registerAdd(
      ref,
      AddAction(label: 'Add quote', run: (ctx) => ctx.push(Routes.addQuote)),
    );

    final all = ref.watch(quotesProvider).valueOrNull ?? const [];
    final visible = ref.watch(visibleQuotesProvider);
    final tab = ref.watch(quoteTabProvider);
    final searchOpen = ref.watch(quoteSearchOpenProvider);
    final query = ref.watch(quoteSearchProvider);
    final filterCount = ref.watch(quoteFiltersProvider).activeCount;

    const tabKeys = ['all', 'draft', 'sent', 'accepted', 'rejected', 'expired'];

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Quotes',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () => ref.read(quoteSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
            ),
            if (searchOpen) ...[
              SizedBox(height: 12.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search quotes…',
                onChanged: (v) => ref.read(quoteSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(quoteSearchProvider.notifier).state = '';
                  ref.read(quoteSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 10.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final k in tabKeys)
                    TabChip(
                      label: '${k == 'all' ? 'All' : StatusMeta$.quote[k]!.label} (${quoteTabCount(all, k)})',
                      active: tab == k,
                      onTap: () => ref.read(quoteTabProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _savedViewRow(filterCount),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: visible.isEmpty
              ? ListView(
                  children: [
                    EmptyState(
                      icon: PhosphorIconsRegular.fileText,
                      title: 'No quotes found',
                      body: 'Try a different status, clear filters, or create a new quote.',
                      ctaLabel: 'Add quote',
                      ctaIcon: PhosphorIconsBold.plus,
                      onCta: () => context.push(Routes.addQuote),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (context, i) {
                    final quote = visible[i];
                    return QuoteCard(
                      quote: quote,
                      onTap: () => context.push('${Routes.quoteDetail}?id=${quote.id}'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    final spec = ref.read(quotesFilterSpecProvider);
    final current = ref.read(quoteFiltersProvider);
    final base = ref.read(quotesProvider).valueOrNull ?? const [];
    final activeView = ref.read(quoteSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((q) => quoteMatchesFilters(q, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: (name, draft) {
        ref.read(quoteSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(quoteFiltersProvider.notifier).state = result;
    final views = ref.read(quoteSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(quoteSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(quoteSavedViewsProvider);
    return SavedChipRow(
      views: [for (final v in saved.views) SavedView(v.id, v.name)],
      active: {if (saved.activeId != null) saved.activeId!},
      showClearAlways: filterCount > 0,
      onToggle: _toggleView,
      onClear: _clearFilters,
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(quoteSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(quoteSavedViewsProvider.notifier).deactivate();
      ref.read(quoteFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(quoteSavedViewsProvider.notifier).apply(id);
    ref.read(quoteFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(quoteSavedViewsProvider.notifier).clearActive();
    ref.read(quoteFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
