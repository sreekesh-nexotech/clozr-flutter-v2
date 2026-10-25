import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/payments_filter_spec.dart';
import '../../application/payments_list_view.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/payment.dart';
import '../components/invoice_card.dart';
import '../components/mode_toggle.dart';
import '../components/payment_card.dart';
import '../components/record_payment_sheet.dart';
import '../components/saved_chip_row.dart';

/// CRM › Payments — the webapp's two tabs, Payment plans (the landing tab)
/// and Payments (the individual records), as a mode toggle over two
/// status-chip lists sharing one header and search field. "Record payment"
/// is the contextual `+` on both. The Payments mode is wired to the
/// spec-driven filter engine (drawer → matcher → badge → saved views),
/// mirroring the Leads reference.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // A query left behind by a collapsed box would filter the list with
    // nothing on screen saying so; only keep it while the box is open.
    if (!ref.read(paySearchOpenProvider) && ref.read(paySearchProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(paySearchProvider.notifier).state = '';
      });
    } else {
      _searchCtrl.text = ref.read(paySearchProvider);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Record payment sheet.
    registerAdd(
      ref,
      AddAction(label: 'Record payment', module: 'payment', run: (ctx) => showRecordPaymentSheet(ctx)),
    );

    final mode = ref.watch(payModeProvider);
    final isPayments = mode == 'payments';
    final searchOpen = ref.watch(paySearchOpenProvider);
    final query = ref.watch(paySearchProvider);

    final allPayments = ref.watch(allPaymentsProvider);
    final allInvoices = ref.watch(invoicesProvider).valueOrNull ?? const [];
    final payTab = ref.watch(payTabProvider);
    final invTab = ref.watch(invTabProvider);
    final filterCount = ref.watch(paymentFiltersProvider).activeCount;

    const payTabKeys = ['all', 'paid', 'due', 'overdue', 'scheduled'];
    const invTabKeys = ['all', 'unpaid', 'partial', 'completed'];

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Payments',
              hasSearchQuery: query.isNotEmpty,
              filterCount: isPayments ? filterCount : 0,
              onSearch: () {
                // Collapsing the box drops the query, like clearing the webapp's
                // search box — a hidden query would keep narrowing the list.
                if (searchOpen) {
                  _searchCtrl.clear();
                  ref.read(paySearchProvider.notifier).state = '';
                }
                ref.read(paySearchOpenProvider.notifier).state = !searchOpen;
              },
              onFilter: isPayments ? _openFilters : null,
            ),
            SizedBox(height: 14.h),
            ModeToggle(
              options: const [
                ModeOption(PhosphorIconsRegular.fileText, 'Payment plans'),
                ModeOption(PhosphorIconsRegular.wallet, 'Payments'),
              ],
              selectedIndex: isPayments ? 1 : 0,
              onChanged: (i) => ref.read(payModeProvider.notifier).state = i == 0 ? 'invoices' : 'payments',
            ),
            SizedBox(height: 14.h),
            if (searchOpen) ...[
              SearchField(
                controller: _searchCtrl,
                hint: isPayments ? 'Search payments..' : 'Search payment plans, customer, quote..',
                onChanged: (v) => ref.read(paySearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(paySearchProvider.notifier).state = '';
                  ref.read(paySearchOpenProvider.notifier).state = false;
                },
              ),
              SizedBox(height: 14.h),
            ],
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: isPayments
                    ? [
                        for (final k in payTabKeys)
                          TabChip(
                            label: '${k == 'all' ? 'All' : StatusMeta$.payment[k]!.label} (${payTabCount(allPayments, k)})',
                            active: payTab == k,
                            onTap: () => ref.read(payTabProvider.notifier).state = k,
                          ),
                      ]
                    : [
                        for (final k in invTabKeys)
                          TabChip(
                            label: '${k == 'all' ? 'All' : StatusMeta$.invoice[k]!.label} (${invTabCount(allInvoices, k)})',
                            active: invTab == k,
                            onTap: () => ref.read(invTabProvider.notifier).state = k,
                          ),
                      ],
              ),
            ),
            if (isPayments) ...[
              SizedBox(height: 12.h),
              _savedViewRow(filterCount),
            ],
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(child: isPayments ? _paymentsList(context, ref) : _invoicesList(context, ref)),
      ],
    );
  }

  // ── Filter drawer (Payments mode) ──
  /// Pull-to-refresh, covering **both** segments rather than the visible one:
  /// the Payments/Invoices toggle switches without refetching, so refreshing
  /// only one would leave the other showing rows from before the pull.
  Future<void> _refresh() async {
    ref.invalidate(paymentsProvider);
    ref.invalidate(invoicesProvider);
    ref.invalidate(paymentListSchemaFutureProvider);
    await settle([
      ref.read(paymentsProvider.future),
      ref.read(invoicesProvider.future),
      ref.read(paymentListSchemaFutureProvider.future),
    ]);
  }

  Future<void> _openFilters() async {
    final spec = ref.read(paymentsFilterSpecProvider);
    final current = ref.read(paymentFiltersProvider);
    final base = ref.read(allPaymentsProvider);
    final activeView = ref.read(paymentSavedViewsProvider).active;
    // The same API-backed lookup the drawer's Customer options were built from,
    // so the preview count and the applied filter agree on what a payment's
    // company is.
    final lookup = ref.read(crmPartyLookupProvider);

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) =>
          base.where((p) => paymentMatchesFilters(p, draft, lookup)).length,
      activeViewName: activeView?.name,
      existingViewNames: ref.read(paymentSavedViewsProvider).views.map((v) => v.name).toSet(),
      onSaveView: (name, draft) {
        ref.read(paymentSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(paymentFiltersProvider.notifier).state = result;
    final views = ref.read(paymentSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(paymentSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  /// Deletes a saved view after the chip's confirm. Removing the applied view
  /// also clears its filters.
  void _removeView(String id) {
    final wasActive = ref.read(paymentSavedViewsProvider).activeId == id;
    ref.read(paymentSavedViewsProvider.notifier).remove(id);
    if (wasActive) ref.read(paymentFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('View removed');
  }

  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(paymentSavedViewsProvider);
    return SavedChipRow(
      views: [for (final v in saved.views) SavedView(v.id, v.name)],
      active: {if (saved.activeId != null) saved.activeId!},
      showClearAlways: filterCount > 0,
      onToggle: _toggleView,
      onClear: _clearFilters,
      onRemove: _removeView,
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(paymentSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(paymentSavedViewsProvider.notifier).deactivate();
      ref.read(paymentFiltersProvider.notifier).state = FilterValues();
      return;
    }
    // The chip was built from an earlier snapshot of the saved-view list. If
    // the view was deleted or renamed elsewhere between render and tap,
    // `firstWhere` threw a StateError inside a tap handler - a red screen in
    // debug, a swallowed tap in release. Fail inert and say so instead.
    final view = saved.views.where((v) => v.id == id).firstOrNull;
    if (view == null) {
      ref.read(toastProvider.notifier).show('That view is no longer available.');
      return;
    }
    ref.read(paymentSavedViewsProvider.notifier).apply(id);
    ref.read(paymentFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  /// Whether a search, status chip or drawer filter is narrowing the list —
  /// the webapp then says "match your filters" instead of "yet".
  bool _isNarrowed() =>
      ref.read(paySearchProvider).trim().isNotEmpty ||
      ref.read(paymentFiltersProvider).activeCount > 0 ||
      ref.read(payTabProvider) != 'all';

  /// The empty state's "Clear filters": search, chip and drawer back to all.
  void _resetListView() {
    _searchCtrl.clear();
    ref.read(paySearchProvider.notifier).state = '';
    ref.read(payTabProvider.notifier).state = 'all';
    _clearFilters();
  }

  void _clearFilters() {
    ref.read(paymentSavedViewsProvider.notifier).clearActive();
    ref.read(paymentFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }

  Widget _paymentsList(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentsProvider);
    return AsyncStateView<List<Payment>>(
      value: async,
      onRetry: () => ref.invalidate(paymentsProvider),
      onRefresh: _refresh,
      error: (e, retry) => _loadError("Couldn't load payments", e, retry),
      data: (_) {
        final visible = ref.watch(visiblePaymentsProvider);
        if (visible.isEmpty) {
          return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _isNarrowed()
                  ? EmptyState(
                      icon: PhosphorIconsRegular.funnel,
                      title: 'No payments match your filters',
                      body: 'Try widening your search or clearing a filter to see more.',
                      ctaLabel: 'Clear filters',
                      ctaIcon: PhosphorIconsBold.xCircle,
                      onCta: _resetListView,
                    )
                  // Payments aren't created here — they come from an accepted
                  // quote's schedule, so the way forward is the quotes list.
                  : EmptyState(
                      icon: PhosphorIconsRegular.wallet,
                      title: 'No payments yet',
                      body: 'Payments appear here once a quote is accepted and its payment schedule is created.',
                      ctaLabel: 'Go to quotes',
                      ctaIcon: PhosphorIconsBold.arrowRight,
                      onCta: () => context.go(Routes.quotes),
                    ),
            ],
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
          // The list scrolls rather than pages, so the webapp's range label
          // reduces to a plain count.
          itemCount: visible.length + 1,
          separatorBuilder: (_, __) => SizedBox(height: 10.h),
          itemBuilder: (context, i) {
            if (i == 0) return _countLabel(paymentCountLabel(visible.length));
            final payment = visible[i - 1];
            return PaymentCard(
              payment: payment,
              onTap: () => _openPayment(payment),
              // Long-press offers the webapp row's actions (View, Delete).
              onLongPress: () => _paymentActions(payment),
            );
          },
        );
      },
    );
  }

  /// The webapp's list error: its own title, the reason, "Try again".
  Widget _loadError(String title, AppError e, VoidCallback retry) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ErrorState(
            title: title,
            body: e.message,
            ctaLabel: 'Try again',
            onRetry: retry,
          ),
        ],
      );

  void _openPayment(Payment p) => context.push('${Routes.paymentDetail}?id=${p.id}');

  // ── Row actions: the webapp row's View / Delete ──

  /// The plan a record belongs to, for its `payment_type`.
  Invoice? _planOf(Payment p) {
    final plans = ref.read(invoicesProvider).valueOrNull ?? const <Invoice>[];
    for (final iv in plans) {
      if (p.planUuid != null && iv.uuid == p.planUuid) return iv;
    }
    for (final iv in plans) {
      if (p.invId != null && iv.id == p.invId) return iv;
    }
    return null;
  }

  Future<void> _paymentActions(Payment p) async {
    // Delete only where the server will allow it: payment delete, a
    // milestone-based plan, nothing paid and no tax document — the rule the
    // webapp's confirm spells out.
    final canDelete = canDeletePaymentRecord(
      p,
      planType: _planOf(p)?.paymentType,
      hasDeletePermission: hasPermission(ref, 'payment', PermVerb.delete),
    );
    await showActionMenu(context, title: paymentWho(p).name, actions: [
      MenuAction(icon: PhosphorIconsRegular.eye, label: 'View', onTap: () => _openPayment(p)),
      if (canDelete)
        MenuAction(
          icon: PhosphorIconsRegular.trash,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDelete(p),
        ),
    ]);
  }

  Future<void> _confirmDelete(Payment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(deleteRecordTitle),
        content: const Text(deleteRecordBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(paymentsRepositoryProvider).deleteRecord(p.id);
    } on AppError catch (e) {
      // Shown here with the server's reason, so the shell must not toast it
      // again in raw form.
      ref.read(apiServiceProvider).handled(e);
      if (mounted) ref.read(toastProvider.notifier).showError(e.bareMessage);
      return;
    }
    if (!mounted) return;
    ref.read(toastProvider.notifier).show(deleteRecordToast);
    // The server recalculates the plan's totals — refetch both lists.
    ref.invalidate(paymentsProvider);
    ref.invalidate(invoicesProvider);
  }

  Widget _invoicesList(BuildContext context, WidgetRef ref) {
    final async = ref.watch(invoicesProvider);
    return AsyncStateView<List<Invoice>>(
      value: async,
      onRetry: () => ref.invalidate(invoicesProvider),
      onRefresh: _refresh,
      error: (e, retry) => _loadError("Couldn't load payment plans", e, retry),
      data: (_) {
        final visible = ref.watch(visibleInvoicesProvider);
        final leads = ref.watch(planLeadNamesProvider);
        final counts = ref.watch(planRecordCountsProvider);
        final schema = ref.watch(paymentListSchemaProvider);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
          children: [
            _countLabel(planCountLabel(visible.length)),
            SizedBox(height: 10.h),
            _invoiceBanner(),
            SizedBox(height: 10.h),
            if (visible.isEmpty)
              const EmptyState(
                icon: PhosphorIconsRegular.fileText,
                title: 'No payment plans match your filters',
                body: 'Try widening your search or picking another status.',
              )
            else
              for (int i = 0; i < visible.length; i++) ...[
                if (i > 0) SizedBox(height: 10.h),
                InvoiceCard(
                  invoice: visible[i],
                  schema: schema,
                  leadName: leads[visible[i].uuid],
                  recordCount: counts[visible[i].uuid],
                  onTap: () => context.push('${Routes.invoiceDetail}?id=${visible[i].id}'),
                ),
              ],
          ],
        );
      },
    );
  }

  Widget _invoiceBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 11.h),
      decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(12.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.info, size: 16.sp, color: AppColors.blueBright),
          SizedBox(width: 9.w),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'A payment plan is generated when a quote is accepted. It groups that customer\u2019s installments and rolls up to ',
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: _bannerText, height: 1.5),
                children: [
                  TextSpan(text: 'Completed', style: AppText.custom(size: 12, weight: FontWeight.w700, color: _bannerText)),
                  TextSpan(text: ' once every installment settles.', style: AppText.custom(size: 12, weight: FontWeight.w500, color: _bannerText)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "6 payment plans" / "19 payments" — the webapp's list counter.
Widget _countLabel(String text) => Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
    );

/// The prototype's `#35507C` info-banner text — no design token exists for it.
const Color _bannerText = Color(0xFF35507C);
