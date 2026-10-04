import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../crm/presentation/components/mode_toggle.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/documents_filter_spec.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../components/acc_widgets.dart';
import '../components/document_card.dart';

/// Invoices (plan §4.2) — sales documents, paged from the server: an
/// Invoices | Credit notes toggle over status tabs, server-side filters and a
/// number search, in the Payments screen's layout.
class AccInvoicesScreen extends ConsumerStatefulWidget {
  const AccInvoicesScreen({super.key});

  @override
  ConsumerState<AccInvoicesScreen> createState() => _AccInvoicesScreenState();
}

class _AccInvoicesScreenState extends ConsumerState<AccInvoicesScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  static const _tabs = {'all': 'All', 'DRAFT': 'Draft', 'ISSUED': 'Issued', 'CANCELLED': 'Cancelled'};

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(accDocSearchProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    // One request per pause, not per keystroke.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) ref.read(accDocSearchProvider.notifier).state = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(accPermProvider('acc_document')).create;
    registerAdd(
      ref,
      canCreate ? AddAction(label: 'New invoice', run: (ctx) => ctx.push(Routes.accNewInvoice)) : null,
    );

    final credit = ref.watch(accDocModeProvider) == 'credit';
    final tab = ref.watch(accDocTabProvider);
    final searchOpen = ref.watch(accDocSearchOpenProvider);
    final query = ref.watch(accDocSearchProvider);
    final filterCount = ref.watch(accDocFiltersProvider).activeCount;

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Invoices',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () => ref.read(accDocSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
            ),
            SizedBox(height: 14.h),
            ModeToggle(
              options: const [
                ModeOption(PhosphorIconsRegular.receipt, 'Invoices'),
                ModeOption(PhosphorIconsRegular.arrowUUpLeft, 'Credit notes'),
              ],
              selectedIndex: credit ? 1 : 0,
              onChanged: (i) {
                ref.read(accDocModeProvider.notifier).state = i == 0 ? 'invoices' : 'credit';
                // The type filter belongs to the invoice family only.
                ref.read(accDocFiltersProvider.notifier).state = FilterValues();
              },
            ),
            SizedBox(height: 14.h),
            if (searchOpen) ...[
              SearchField(
                controller: _searchCtrl,
                hint: 'Search by number…',
                onChanged: _onSearch,
                onClose: () {
                  _debounce?.cancel();
                  _searchCtrl.clear();
                  ref.read(accDocSearchProvider.notifier).state = '';
                  ref.read(accDocSearchOpenProvider.notifier).state = false;
                },
              ),
              SizedBox(height: 14.h),
            ],
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final e in _tabs.entries)
                    TabChip(
                      label: e.value,
                      active: tab == e.key,
                      onTap: () => ref.read(accDocTabProvider.notifier).state = e.key,
                    ),
                ],
              ),
            ),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(child: AccountingGate(child: _list(credit, canCreate))),
      ],
    );
  }

  Widget _list(bool credit, bool canCreate) {
    final q = ref.watch(accDocQueryProvider);
    final state = ref.watch(docListProvider(q));
    final ctrl = ref.read(docListProvider(q).notifier);

    Future<void> refresh() async {
      await ctrl.refresh();
    }

    if (state.loading && state.items.isEmpty) return const ListSkeleton();
    if (state.error != null && state.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [ErrorState.forError(state.error!, onRetry: refresh)],
      );
    }
    if (state.items.isEmpty) {
      return AppRefresh(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            EmptyState(
              icon: credit ? PhosphorIconsRegular.arrowUUpLeft : PhosphorIconsRegular.receipt,
              title: credit ? 'No credit notes' : 'No invoices found',
              body: credit
                  ? 'Credit notes raised against issued invoices show up here.'
                  : 'Try a different status, clear filters, or raise a new invoice.',
              ctaLabel: !credit && canCreate ? 'New invoice' : null,
              ctaIcon: PhosphorIconsBold.plus,
              onCta: () => context.push(Routes.accNewInvoice),
            ),
          ],
        ),
      );
    }
    return AppRefresh(
      onRefresh: refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) ctrl.loadMore();
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
          itemCount: state.items.length + (state.hasMore ? 1 : 0),
          separatorBuilder: (_, __) => SizedBox(height: 10.h),
          itemBuilder: (context, i) {
            if (i >= state.items.length) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 12.h),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy),
                  ),
                ),
              );
            }
            final d = state.items[i];
            return DocumentCard(
              document: d,
              onTap: () => context.push('${Routes.accDocumentDetail}?id=${d.id}'),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openFilters() async {
    final credit = ref.read(accDocModeProvider) == 'credit';
    final spec = ref.read(documentsFilterSpecProvider(credit));
    final loaded = ref.read(docListProvider(ref.read(accDocQueryProvider))).items;
    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: ref.read(accDocFiltersProvider),
      // A preview over the rows already loaded; the list itself refetches
      // with the filters applied server-side.
      previewCount: (draft) => loaded.where((d) => documentMatchesFilters(d, draft, creditNotes: credit)).length,
    );
    if (result == null) return;
    ref.read(accDocFiltersProvider.notifier).state = result;
    ref.read(toastProvider.notifier).show('Filters applied');
  }
}
