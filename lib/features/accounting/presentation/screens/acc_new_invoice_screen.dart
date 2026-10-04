import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../crm/application/providers/crm_party_providers.dart';
import '../../../operations/presentation/components/ops_form_scaffold.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../components/acc_pickers.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';
import '../sheets/acc_sheet_scaffold.dart';

/// One line of the invoice being composed.
class _Line {
  const _Line({
    required this.description,
    this.productId,
    this.hsnSac = '',
    this.nature = 'SERVICE',
    this.qty = '1',
    this.unitPrice = '0.00',
    this.discount,
    this.treatment = 'TAXABLE',
  });

  final String description;
  final String? productId;
  final String hsnSac;
  final String nature;
  final String qty;
  final String unitPrice;
  final String? discount;
  final String treatment;

  Map<String, Object?> toJson(int lineNo) => {
        'line_no': lineNo,
        if (productId != null) 'product': productId,
        'description': description,
        if (hsnSac.isNotEmpty) 'hsn_sac': hsnSac,
        'supply_nature': nature,
        'qty': qty,
        'unit_price': unitPrice,
        if (discount != null && !moneyIsZero(discount)) 'line_discount': discount,
        'tax_treatment': treatment,
      };
}

/// New invoice (plan §4.4) — a manual draft: header, then lines from the
/// catalog or typed in. No totals are computed here; the draft's detail page
/// previews the real tax before issue.
class AccNewInvoiceScreen extends ConsumerStatefulWidget {
  const AccNewInvoiceScreen({super.key});

  @override
  ConsumerState<AccNewInvoiceScreen> createState() => _AccNewInvoiceScreenState();
}

class _AccNewInvoiceScreenState extends ConsumerState<AccNewInvoiceScreen> {
  String _docType = 'TAX_INVOICE';
  String? _customerId;
  DateTime _date = DateTime.now();
  DateTime? _supplyDate;
  DateTime? _dueDate;
  String? _pos;
  String? _amountsAre;
  final _narration = TextEditingController();
  final List<_Line> _lines = [];
  bool _busy = false;
  AppError? _error;

  bool get _dirty => _customerId != null || _lines.isNotEmpty || _narration.text.isNotEmpty;

  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `?customer=` when raised from a customer's page.
    if (!_prefilled) {
      _prefilled = true;
      _customerId = GoRouterState.of(context).uri.queryParameters['customer'];
    }
  }

  @override
  void initState() {
    super.initState();
    // The tenant's usual basis, when setup is readable.
    ref.read(tenantProfileProvider.future).then((p) {
      if (mounted && _amountsAre == null && p?.defaultAmountsAre != null) {
        setState(() => _amountsAre = p!.defaultAmountsAre);
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _narration.dispose();
    super.dispose();
  }

  Future<void> _addProduct() async {
    final p = await pickProduct(context, ref);
    if (p == null || !mounted) return;
    final nature = p.raw['supply_nature'];
    final line = await _showLineSheet(
      context,
      _Line(
        description: p.name,
        productId: p.id,
        hsnSac: p.hsn,
        nature: nature is String && nature.isNotEmpty ? nature : 'SERVICE',
        unitPrice: toMoneyStr(p.priceNum),
      ),
    );
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _addFree() async {
    final line = await _showLineSheet(context, const _Line(description: ''));
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_lines.isEmpty) {
      ref.read(toastProvider.notifier).showError('Add at least one line');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final doc = await ref.read(accountingRepositoryProvider).createInvoice({
        'doc_type': _docType,
        'document_date': isoDay(_date),
        'supply_date': _supplyDate == null ? null : isoDay(_supplyDate!),
        'due_date': _dueDate == null ? null : isoDay(_dueDate!),
        'customer': _customerId,
        'place_of_supply_state_code': _pos,
        'amounts_are': _amountsAre,
        'narration': _narration.text.trim(),
        'lines': [for (int i = 0; i < _lines.length; i++) _lines[i].toJson(i + 1)],
      });
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Draft created');
      if (doc != null) {
        context.pushReplacement('${Routes.accDocumentDetail}?id=${doc.id}');
      } else {
        context.pop();
      }
    } on AppError catch (e) {
      // No retry on a timeout: the create takes no idempotency key and each
      // call makes a new draft (§12.1). The user checks the list instead.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final party = ref.watch(crmPartyLookupProvider)(custId: _customerId);
    final stateName = ref.watch(gstStateNameProvider);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) handleEditClose(context, dirty: true);
      },
      child: OpsFormScaffold(
        title: 'New invoice',
        ctaLabel: _busy ? 'Creating…' : 'Create draft',
        ctaEnabled: !_busy && _lines.isNotEmpty && isOnline(ref),
        onClose: () => handleEditClose(context, dirty: _dirty),
        onSubmit: _submit,
        children: [
          if (_error != null) ...[
            ConflictBanner(error: _error!),
            SizedBox(height: 14.h),
          ],
          const OpsSectionLabel('Invoice', first: true),
          AccChoiceChips(
            options: {for (final t in manualInvoiceTypes) t: docTypeLabels[t]!},
            selected: _docType,
            onSelected: (v) => setState(() => _docType = v),
          ),
          SizedBox(height: 14.h),
          AccPickerBox(
            label: 'Customer',
            value: party?.name ?? (_customerId == null ? null : 'Customer'),
            hint: 'Select customer…',
            icon: PhosphorIconsRegular.magnifyingGlass,
            footnote: 'Needed before the invoice can be issued.',
            onTap: () async {
              final c = await pickCustomer(context, ref, selectedId: _customerId);
              if (c != null) setState(() => _customerId = c.id);
            },
          ),
          SizedBox(height: 14.h),
          AccDateBox(label: 'Invoice date', required: true, value: _date, showIstHint: true,
              onChanged: (d) => setState(() => _date = d ?? _date)),
          SizedBox(height: 14.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AccDateBox(label: 'Supply date', value: _supplyDate, clearable: true,
                    onChanged: (d) => setState(() => _supplyDate = d)),
              ),
              SizedBox(width: 9.w),
              Expanded(
                child: AccDateBox(label: 'Due date', value: _dueDate, clearable: true,
                    onChanged: (d) => setState(() => _dueDate = d)),
              ),
            ],
          ),
          const OpsSectionLabel('Tax'),
          AccPickerBox(
            label: 'Place of supply',
            value: _pos == null ? null : stateName(_pos),
            hint: 'From the customer (automatic)',
            icon: PhosphorIconsRegular.mapPin,
            onTap: () async {
              final code = await pickGstState(context, ref, selected: _pos);
              if (code != null) setState(() => _pos = code);
            },
          ),
          SizedBox(height: 14.h),
          AccChoiceChips(
            label: 'Prices are',
            options: amountsAreLabels,
            selected: _amountsAre,
            onSelected: (v) => setState(() => _amountsAre = v),
          ),
          const OpsSectionLabel('Items'),
          for (int i = 0; i < _lines.length; i++) ...[
            _lineCard(i),
            SizedBox(height: 10.h),
          ],
          Row(
            children: [
              Expanded(child: _addButton(PhosphorIconsRegular.package, 'Add product', _addProduct)),
              SizedBox(width: 10.w),
              Expanded(child: _addButton(PhosphorIconsRegular.plus, 'Add line', _addFree)),
            ],
          ),
          SizedBox(height: 10.h),
          Text('Totals are worked out when you preview the draft.',
              style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          const OpsSectionLabel('Narration'),
          AccInput(label: 'Narration', controller: _narration, hint: 'Shown on the invoice', maxLines: 3,
              onChanged: (_) => setState(() {})),
          if (!isOnline(ref)) const OfflineNote(),
        ],
      ),
    );
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    return ClozrCard(
      radius: 14,
      elevated: false,
      padding: EdgeInsets.all(13.r),
      onTap: () async {
        final edited = await _showLineSheet(context, l);
        if (edited != null) setState(() => _lines[i] = edited);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.description, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 2.h),
                Text(
                  [if (l.hsnSac.isNotEmpty) 'HSN ${l.hsnSac}', label(supplyNatureLabels, l.nature), if (l.productId != null) 'Catalog']
                      .join(' · '),
                  style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                ),
                SizedBox(height: 2.h),
                Text('${l.qty} × ${formatMoneyStr(l.unitPrice)}',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _lines.removeAt(i)),
            child: Padding(
              padding: EdgeInsets.all(4.r),
              child: Icon(PhosphorIconsRegular.trash, size: 18.sp, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addButton(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(color: const Color(0xFFE6E7EA)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16.sp, color: AppColors.textSecondary),
              SizedBox(width: 7.w),
              Text(label, style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBody)),
            ],
          ),
        ),
      );
}

/// Adds or edits one invoice line. HSN/SAC is 4–8 digits when given — the
/// server rejects anything else, and a code too short for the turnover band
/// blocks issue later (`HSN_DIGITS_REQUIRED`), when lines can no longer change.
Future<_Line?> _showLineSheet(BuildContext context, _Line initial) =>
    showClozrSheet<_Line>(context: context, builder: (_) => _LineSheet(initial: initial));

class _LineSheet extends StatefulWidget {
  const _LineSheet({required this.initial});
  final _Line initial;

  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  late final _desc = TextEditingController(text: widget.initial.description);
  late final _hsn = TextEditingController(text: widget.initial.hsnSac);
  late final _qty = TextEditingController(text: widget.initial.qty);
  late final _price = TextEditingController(text: widget.initial.unitPrice);
  late final _discount = TextEditingController(text: widget.initial.discount ?? '');
  late String _nature = widget.initial.nature;
  late String _treatment = widget.initial.treatment;
  String? _hsnError;

  @override
  void dispose() {
    for (final c in [_desc, _hsn, _qty, _price, _discount]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final hsn = _hsn.text.trim();
    if (_desc.text.trim().isEmpty) return;
    if (hsn.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(hsn)) {
      setState(() => _hsnError = 'HSN/SAC must be 4 to 8 digits');
      return;
    }
    final price = moneyInput(_price.text);
    final qty = double.tryParse(_qty.text.trim());
    if (price == null || qty == null || qty <= 0) return;
    Navigator.of(context).pop(_Line(
      description: _desc.text.trim(),
      productId: widget.initial.productId,
      hsnSac: hsn,
      nature: _nature,
      qty: _qty.text.trim(),
      unitPrice: price,
      discount: moneyInput(_discount.text),
      treatment: _treatment,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ok = _desc.text.trim().isNotEmpty &&
        moneyInput(_price.text) != null &&
        (double.tryParse(_qty.text.trim()) ?? 0) > 0;
    return AccSheetScaffold(
      title: widget.initial.description.isEmpty ? 'Add line' : 'Edit line',
      submitLabel: 'Save line',
      posts: false,
      submitEnabled: ok,
      onSubmit: _save,
      children: [
        AccInput(label: 'Description', required: true, controller: _desc, hint: 'What is being billed',
            textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {})),
        AccInput(
          label: 'HSN / SAC',
          controller: _hsn,
          hint: '4 to 8 digits',
          errorText: _hsnError,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
          onChanged: (_) => setState(() => _hsnError = null),
        ),
        AccChoiceChips(label: 'Nature', options: supplyNatureLabels, selected: _nature,
            onSelected: (v) => setState(() => _nature = v)),
        Row(
          children: [
            Expanded(
              child: AccInput(
                label: 'Qty',
                required: true,
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(width: 9.w),
            Expanded(child: MoneyField(label: 'Unit price', required: true, controller: _price, onChanged: (_) => setState(() {}))),
          ],
        ),
        MoneyField(label: 'Discount', controller: _discount, hint: 'Optional'),
        AccChoiceChips(
          label: 'Tax treatment',
          options: const {'TAXABLE': 'Taxable', 'NIL': 'Nil rated', 'EXEMPT': 'Exempt', 'NON_GST': 'Non-GST'},
          selected: _treatment,
          onSelected: (v) => setState(() => _treatment = v),
        ),
      ],
    );
  }
}
