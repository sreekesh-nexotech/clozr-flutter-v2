import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../crm/application/providers/customers_providers.dart';
import '../../../crm/application/providers/products_providers.dart';
import '../../../crm/domain/entities/customer.dart';
import '../../../crm/domain/entities/product.dart';
import '../../../crm/presentation/components/lead_picker_sheet.dart' show ClozrDividerLine;
import '../../../crm/presentation/sheets/add_sheet_kit.dart' show initialsOf;
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_masters.dart';
import '../config/accounting_copy.dart';

/// One row a [showSearchPicker] can list.
class PickItem<T> {
  const PickItem(this.value, this.title, {this.subtitle, this.initials, this.searchText});

  final T value;
  final String title;
  final String? subtitle;

  /// Shown in the leading chip; omit for a plain text row.
  final String? initials;

  /// Extra text the search matches beyond [title] / [subtitle].
  final String? searchText;
}

/// A searchable single-choice sheet in the lead picker's style: title, search
/// field, rows with an initials chip and a caret. Searches the list in memory.
Future<T?> showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required List<PickItem<T>> items,
  String hint = 'Search…',
  String empty = 'Nothing matches',
  bool loading = false,
  T? selected,
}) {
  return showClozrSheet<T>(
    context: context,
    builder: (_) => _SearchPicker<T>(
      title: title,
      items: items,
      hint: hint,
      empty: empty,
      loading: loading,
      selected: selected,
    ),
  );
}

class _SearchPicker<T> extends StatefulWidget {
  const _SearchPicker({
    required this.title,
    required this.items,
    required this.hint,
    required this.empty,
    required this.loading,
    this.selected,
  });

  final String title;
  final List<PickItem<T>> items;
  final String hint;
  final String empty;
  final bool loading;
  final T? selected;

  @override
  State<_SearchPicker<T>> createState() => _SearchPickerState<T>();
}

class _SearchPickerState<T> extends State<_SearchPicker<T>> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<PickItem<T>> get _matches {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return [
      for (final i in widget.items)
        if (i.title.toLowerCase().contains(q) ||
            (i.subtitle ?? '').toLowerCase().contains(q) ||
            (i.searchText ?? '').toLowerCase().contains(q))
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Padding(
      padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 18.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
          SizedBox(height: 12.h),
          if (widget.items.length > 6) ...[
            SearchField(
              controller: _ctrl,
              hint: widget.hint,
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              onClose: () {
                _ctrl.clear();
                setState(() => _q = '');
              },
            ),
            SizedBox(height: 10.h),
          ],
          Flexible(
            child: widget.loading
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 28.h),
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy)),
                  )
                : matches.isEmpty
                    ? Padding(
                        padding: EdgeInsets.symmetric(vertical: 28.h),
                        child: Center(
                          child: Text(widget.empty,
                              textAlign: TextAlign.center,
                              style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: matches.length,
                        separatorBuilder: (_, __) => const ClozrDividerLine(),
                        itemBuilder: (_, i) => _row(matches[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _row(PickItem<T> item) {
    final on = widget.selected != null && widget.selected == item.value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(item.value),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        child: Row(
          children: [
            if (item.initials != null) ...[
              Container(
                width: 38.w,
                height: 38.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(11.r)),
                child: Text(item.initials!,
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)),
              ),
              SizedBox(width: 12.w),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  if ((item.subtitle ?? '').isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
            if (on)
              Icon(PhosphorIconsBold.check, size: 18.sp, color: AppColors.success)
            else
              Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
          ],
        ),
      ),
    );
  }
}

// ── Concrete pickers ──

/// A customer from the CRM list the app already loads — document rows carry
/// ids only, and the customer endpoint is where names live (§12.5).
Future<Customer?> pickCustomer(BuildContext context, WidgetRef ref, {String? selectedId}) async {
  final async = ref.read(customersProvider);
  final customers = async.valueOrNull ?? await ref.read(customersProvider.future).catchError((_) => <Customer>[]);
  if (!context.mounted) return null;
  final id = await showSearchPicker<String>(
    context: context,
    title: 'Select customer',
    hint: 'Search by name or company',
    empty: 'No matching customer',
    selected: selectedId,
    items: [
      for (final c in customers)
        PickItem(c.id, c.name,
            subtitle: c.company, initials: c.initials.isEmpty ? initialsOf(c.name) : c.initials),
    ],
  );
  if (id == null) return null;
  return customers.where((c) => c.id == id).firstOrNull;
}

Future<Vendor?> pickVendor(BuildContext context, WidgetRef ref, {String? selectedId}) async {
  final vendors = ref.read(vendorsProvider).valueOrNull ??
      await ref.read(vendorsProvider.future).catchError((_) => <Vendor>[]);
  if (!context.mounted) return null;
  final active = [for (final v in vendors) if (v.isActive) v];
  final id = await showSearchPicker<String>(
    context: context,
    title: 'Select vendor',
    hint: 'Search vendors',
    empty: 'No vendors yet — add one from the Vendors screen.',
    selected: selectedId,
    items: [
      for (final v in active)
        PickItem(v.id, v.name, subtitle: v.legalName, initials: initialsOf(v.name)),
    ],
  );
  if (id == null) return null;
  return active.where((v) => v.id == id).firstOrNull;
}

/// Catalog products (not packages — a package line is exploded server-side on
/// quotes only; a manual invoice takes plain lines).
Future<Product?> pickProduct(BuildContext context, WidgetRef ref) async {
  final products = ref.read(productsProvider).valueOrNull ??
      await ref.read(productsProvider.future).catchError((_) => <Product>[]);
  if (!context.mounted) return null;
  final usable = [for (final p in products) if (p.active && !p.isPackage) p];
  final id = await showSearchPicker<String>(
    context: context,
    title: 'Add product',
    hint: 'Search products',
    empty: 'No matching product',
    items: [
      for (final p in usable)
        PickItem(p.id, p.name,
            subtitle: [if (p.hsn.isNotEmpty) 'HSN ${p.hsn}', p.price].join(' · '),
            searchText: '${p.code} ${p.hsn}'),
    ],
  );
  if (id == null) return null;
  return usable.where((p) => p.id == id).firstOrNull;
}

/// A GST state. Returns its two-digit code.
Future<String?> pickGstState(BuildContext context, WidgetRef ref, {String? selected, String title = 'Place of supply'}) async {
  final states = ref.read(gstStatesProvider).valueOrNull ??
      await ref.read(gstStatesProvider.future).catchError((_) => <GstState>[]);
  if (!context.mounted) return null;
  return showSearchPicker<String>(
    context: context,
    title: title,
    hint: 'Search states',
    empty: 'States could not be loaded',
    selected: selected,
    items: [for (final s in states) PickItem(s.code, s.name, subtitle: '${s.code} · ${s.alpha}')],
  );
}

Future<String?> pickTdsNature(BuildContext context, {String? selected}) => showSearchPicker<String>(
      context: context,
      title: 'TDS nature',
      selected: selected,
      items: [for (final e in tdsNatures.entries) PickItem(e.key, e.value)],
    );

Future<ExpenseCategory?> pickExpenseCategory(BuildContext context, {String? selected}) async {
  final key = await showSearchPicker<String>(
    context: context,
    title: 'Expense category',
    hint: 'Search categories',
    selected: selected,
    items: [
      for (final c in expenseCategories)
        PickItem(c.key, c.label,
            subtitle: switch (c.itc) {
              ItcHint.blocked => 'No input credit',
              ItcHint.notApplicable => 'No GST',
              ItcHint.eligible => c.tdsNature == null ? null : 'TDS ${tdsNatures[c.tdsNature]}',
            }),
    ],
  );
  return key == null ? null : expenseCategories.firstWhere((c) => c.key == key);
}

/// A bank account from the org's list — BANK kind only unless [kinds] says
/// otherwise.
Future<BankAccount?> pickBankAccount(BuildContext context, WidgetRef ref,
    {String? selectedId, Set<String> kinds = const {'BANK'}}) async {
  final accounts = await ref.read(bankAccountsProvider.future).catchError((_) => <BankAccount>[]);
  if (!context.mounted) return null;
  final usable = [for (final a in accounts) if (kinds.contains(a.kind)) a];
  final id = await showSearchPicker<String>(
    context: context,
    title: 'Bank account',
    empty: 'No bank accounts are set up. Add one on the web app.',
    selected: selectedId,
    items: [
      for (final a in usable)
        PickItem(a.id, a.name, subtitle: [a.accountNoMasked ?? '', if (a.isDefault) 'Default'].where((s) => s.isNotEmpty).join(' · ')),
    ],
  );
  if (id == null) return null;
  return usable.where((a) => a.id == id).firstOrNull;
}
