import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/presentation/components/crm_detail_parts.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../../domain/entities/acc_masters.dart';
import '../../domain/entities/acc_settlement.dart';
import '../components/acc_widgets.dart';
import '../components/document_card.dart';
import '../config/accounting_copy.dart';
import '../sheets/acc_sheet_scaffold.dart';
import '../sheets/party_tax_profile_sheet.dart';
import '../sheets/record_expense_sheet.dart';
import '../sheets/settlement_detail_sheet.dart';
import '../sheets/vendor_form_sheet.dart';
import '../sheets/vendor_payment_sheet.dart';

/// Vendor detail (plan §4.10) — who they are, their bills, what was paid,
/// advances, and the statement; edit, tax profile and deactivate in the menu.
class AccVendorDetailScreen extends ConsumerStatefulWidget {
  const AccVendorDetailScreen({super.key});

  @override
  ConsumerState<AccVendorDetailScreen> createState() => _AccVendorDetailScreenState();
}

class _AccVendorDetailScreenState extends ConsumerState<AccVendorDetailScreen> {
  int _tab = 0;
  static const _tabs = ['Bills', 'Payments', 'Advances', 'Info'];

  String get _id => GoRouterState.of(context).uri.queryParameters['id'] ?? '';

  Future<void> _refresh() async {
    final id = _id;
    ref.invalidate(vendorDetailProvider(id));
    ref.invalidate(billsForVendorProvider(id));
    ref.invalidate(vendorPaymentsProvider(id));
    ref.invalidate(vendorAdvancesProvider(id));
    await settle([ref.read(vendorDetailProvider(id).future)]);
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;
    final async = ref.watch(vendorDetailProvider(id));
    final v = async.valueOrNull;
    final perms = ref.watch(accPermProvider('acc_purchase'));
    final settle = ref.watch(accPermProvider('acc_settlement'));
    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Vendor',
            name: v?.name,
            onBack: () => context.pop(),
            trailing: v == null ? null : DetailIconAction(icon: PhosphorIconsBold.dotsThreeVertical, onTap: () => _menu(v)),
          ),
          Expanded(
            child: AccountingGate(
              child: async.when(
                skipLoadingOnRefresh: true,
                loading: () => const DetailSkeleton(),
                error: (e, _) => ErrorState.forError(
                  e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Something went wrong.'),
                  onRetry: _refresh,
                ),
                data: (vendor) => vendor == null
                    ? const EmptyState(
                        icon: PhosphorIconsRegular.storefront,
                        title: 'Vendor not found',
                        body: 'This vendor may have been removed or you no longer have access to it.',
                      )
                    : _body(vendor),
              ),
            ),
          ),
          if (v != null && v.isActive && ref.watch(accountingActiveProvider) && (settle.create || perms.create))
            StickyActionBar(children: [
              if (perms.create)
                Expanded(
                  child: PrimaryButton(
                    label: 'Record expense',
                    icon: PhosphorIconsRegular.shoppingCart,
                    ghost: true,
                    height: 48,
                    onTap: () => showRecordExpenseSheet(context, vendorId: v.id),
                  ),
                ),
              if (perms.create && settle.create) SizedBox(width: 10.w),
              if (settle.create)
                Expanded(
                  child: PrimaryButton(
                    label: 'Pay vendor',
                    icon: PhosphorIconsBold.arrowUp,
                    height: 48,
                    onTap: () => showVendorPaymentSheet(context, vendorId: v.id),
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _body(Vendor v) {
    final stateName = ref.watch(gstStateNameProvider);
    return AppRefresh(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
        children: [
          FinanceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconChip(icon: PhosphorIconsRegular.storefront, size: 46, radius: 13, iconSize: 22),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8.w,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(v.name,
                                  style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                              StatusPill(
                                label: v.isActive ? 'Active' : 'Inactive',
                                color: v.isActive ? AppColors.success : AppColors.textMuted,
                              ),
                            ],
                          ),
                          if ((v.legalName ?? '').isNotEmpty) ...[
                            SizedBox(height: 3.h),
                            Text(v.legalName!, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                          ],
                          if (v.stateCode != null) ...[
                            SizedBox(height: 3.h),
                            Text(stateName(v.stateCode),
                                style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (ref.watch(accPermProvider('acc_report')).read) ...[
                  SizedBox(height: 14.h),
                  PrimaryButton(
                    label: 'Statement',
                    icon: PhosphorIconsRegular.listBullets,
                    ghost: true,
                    height: 44,
                    onTap: () => context.push('${Routes.accReport}?kind=vendor_statement&party=${v.id}'),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 14.h),
          ClozrCard(
            radius: 18,
            padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 6.h),
            child: DetailUnderlineTabs(labels: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          ),
          SizedBox(height: 14.h),
          ...switch (_tab) {
            0 => _bills(v),
            1 => _payments(v),
            2 => _advances(v),
            _ => [_info(v)],
          },
        ],
      ),
    );
  }

  List<Widget> _asyncList<T>(AsyncValue<List<T>> async, Widget empty, Widget Function(T) row, VoidCallback retry) {
    return async.when(
      loading: () => [const ListSkeleton(itemCount: 3)],
      error: (e, _) => [
        ErrorState.forError(e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Could not load.'),
            onRetry: retry),
      ],
      data: (items) => items.isEmpty
          ? [empty]
          : [
              for (int i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(height: 10.h), row(items[i])],
            ],
    );
  }

  List<Widget> _bills(Vendor v) => _asyncList<AccDocument>(
        ref.watch(billsForVendorProvider(v.id)),
        const DetailTabEmpty(icon: PhosphorIconsRegular.fileText, title: 'No bills', body: 'Bills from this vendor show up here.'),
        (d) => DocumentCard(document: d, onTap: () => context.push('${Routes.accDocumentDetail}?id=${d.id}')),
        () => ref.invalidate(billsForVendorProvider(v.id)),
      );

  List<Widget> _payments(Vendor v) => _asyncList<AccVendorPayment>(
        ref.watch(vendorPaymentsProvider(v.id)),
        const DetailTabEmpty(icon: PhosphorIconsRegular.arrowUp, title: 'No payments', body: 'Payments to this vendor show up here.'),
        (p) => ClozrCard(
          radius: 14,
          padding: EdgeInsets.all(13.r),
          onTap: () => showVendorPaymentDetailSheet(context, p),
          child: Row(
            children: [
              const IconChip(icon: PhosphorIconsRegular.arrowUp),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatApiDay(p.date), style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 3.h),
                    Text(
                      [label(sourceAccountLabels, p.sourceAccountKind), if (!moneyIsZero(p.tdsNow)) 'TDS ${formatMoneyStr(p.tdsNow)}']
                          .join(' · '),
                      style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AccPill(StatusMeta$.accPosting, p.status),
                  SizedBox(height: 5.h),
                  Text(formatMoneyStr(p.amount), style: AppText.custom(size: 14.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
        ),
        () => ref.invalidate(vendorPaymentsProvider(v.id)),
      );

  List<Widget> _advances(Vendor v) => _asyncList<AccVendorAdvance>(
        ref.watch(vendorAdvancesProvider(v.id)),
        const DetailTabEmpty(
          icon: PhosphorIconsRegular.hourglassMedium,
          title: 'No advances',
          body: 'Prepayments to this vendor are recorded on the web app and show up here.',
        ),
        (a) => FinanceCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(formatMoneyStr(a.amount),
                        style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                  ),
                  AccPill(StatusMeta$.accBalance, a.status),
                ],
              ),
              if (!moneyIsZero(a.tdsDeducted)) MetaRow(label: 'TDS', value: formatMoneyStr(a.tdsDeducted)),
              MetaRow(label: 'Remaining', value: formatMoneyStr(a.remaining), last: true),
            ],
          ),
        ),
        () => ref.invalidate(vendorAdvancesProvider(v.id)),
      );

  Widget _info(Vendor v) {
    final rows = <(String, String)>[
      ('Email', v.email ?? '—'),
      ('Phone', v.phone ?? '—'),
      ('Address', v.address ?? '—'),
      ('Account no', v.bankAccountNoMasked ?? '—'),
      ('IFSC', v.ifsc ?? '—'),
      ('Body corporate', v.isBodyCorporate ? 'Yes' : 'No'),
      if (v.isGtaFcmOpted) ('GTA forward charge', 'Opted'),
      if (v.isSmallTransporterDeclared) ('Small transporter', 'Declared'),
      if ((v.notes ?? '').isNotEmpty) ('Notes', v.notes!),
    ];
    return FinanceCard(
      title: 'Details',
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) MetaRow(label: rows[i].$1, value: rows[i].$2, last: i == rows.length - 1),
        ],
      ),
    );
  }

  // ── Actions ──

  Future<void> _menu(Vendor v) async {
    final perms = ref.read(accPermProvider('acc_purchase'));
    final setup = ref.read(accPermProvider('acc_setup'));
    await showActionMenu(
      context,
      title: v.name,
      actions: [
        if (perms.update) MenuAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onTap: () => _edit(v)),
        if (setup.read)
          MenuAction(
            icon: PhosphorIconsRegular.identificationCard,
            label: 'Tax profile',
            sublabel: 'GSTIN, PAN, TDS',
            onTap: () => showPartyTaxProfileSheet(context, kind: 'vendor', partyId: v.id, title: 'Tax profile · ${v.name}'),
          ),
        if (perms.update)
          MenuAction(
            icon: v.isActive ? PhosphorIconsRegular.pause : PhosphorIconsRegular.play,
            label: v.isActive ? 'Deactivate' : 'Activate',
            onTap: () => _setActive(v, !v.isActive),
          ),
        if (perms.delete)
          MenuAction(icon: PhosphorIconsRegular.trash, label: 'Delete', destructive: true, onTap: () => _delete(v)),
      ],
    );
  }

  Future<void> _edit(Vendor v) async {
    final saved = await showVendorFormSheet(context, vendor: v);
    if (saved != null) ref.invalidate(vendorDetailProvider(v.id));
  }

  Future<void> _setActive(Vendor v, bool active) async {
    final toast = ref.read(toastProvider.notifier);
    try {
      // Re-activating can collide with an active vendor of the same name,
      // which the backend answers with a 500 (§12.3).
      if (active && await vendorNameTaken(ref, v.name, exceptId: v.id)) {
        toast.showError(vendorDuplicateMessage);
        return;
      }
      await ref.read(accountingRepositoryProvider).updateVendor(v.id, {'is_active': active});
      invalidateAccountingReads(ref.invalidate);
      ref.invalidate(vendorsProvider);
      ref.invalidate(vendorDetailProvider(v.id));
      toast.show(active ? 'Vendor activated' : 'Vendor deactivated');
    } on AppError catch (e) {
      toast.showError(e.type == AppErrorType.server && active ? vendorDuplicateMessage : e.message);
    }
  }

  Future<void> _delete(Vendor v) async {
    final ok = await confirmAcc(
      context,
      title: 'Delete ${v.name}?',
      body: 'A vendor with any bills or payments cannot be deleted — deactivate it instead.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(accountingRepositoryProvider).deleteVendor(v.id);
      ref.invalidate(vendorsProvider);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Vendor deleted');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      if (e.code == 'PARTY_HAS_BOOKS' && v.isActive) {
        final deactivate = await confirmAcc(
          context,
          title: 'Has accounting history',
          body: '${v.name} has bills or payments, so it cannot be deleted. Deactivate it instead?',
          confirmLabel: 'Deactivate',
        );
        if (deactivate && mounted) await _setActive(v, false);
      } else {
        ref.read(toastProvider.notifier).showError(e.code == null ? e.message : conflictCopy(e).body);
      }
    }
  }
}
