import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/products_providers.dart';
import '../../domain/entities/product.dart';

/// The prototype's `#35507C` info-banner text — no design token exists for it.
const Color _bannerText = Color(0xFF35507C);
const List<String> _unitOptions = [
  'per sq.ft.', 'per unit', 'per seat', 'per room', 'per project',
  'per month', 'per year', 'per package', 'per store',
];

/// Opens the "Add product" / "Add package" sheet (prototype `addProduct`).
/// On submit, inserts the item into the catalog and toasts. [mode] is the
/// active Products-screen mode ('products' | 'packages').
Future<void> showAddProductSheet(BuildContext context, {required String mode}) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _AddProductSheet(isPackage: mode == 'packages'),
  );
}

class _AddProductSheet extends ConsumerStatefulWidget {
  const _AddProductSheet({required this.isPackage});
  final bool isPackage;

  @override
  ConsumerState<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends ConsumerState<_AddProductSheet> {
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _hsn = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();

  /// The category label shown in the picker. Empty = "Uncategorized", which is
  /// not a real type — it is `product_type: null` (`products.md` §8).
  String _cat = '';
  String? _catId;
  String _unit = 'per sq.ft.';

  /// `tax_rate` defaults to **0** on the backend; the old locked "18%" was a
  /// client-side invention that was never sent and never stored (§3).
  int _gst = 0;
  bool _active = true;
  int _seq = 1;

  /// The rates the serializer accepts — anything else is a 400 (§3).
  static const List<int> _gstOptions = [0, 5, 12, 18, 28];

  /// A package needs at least one component before it can be active (§7), and
  /// this sheet has no component editor, so one is created inactive.
  bool get _forcedInactive => widget.isPackage;

  @override
  void dispose() {
    for (final c in [_name, _sku, _hsn, _price, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  void _pick(String title, List<String> options, String current, ValueChanged<String> onPick) {
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: title, onClose: () => Navigator.of(ctx).pop()),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
              children: [
                for (final o in options)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      onPick(o);
                      Navigator.of(ctx).pop();
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 11.h, horizontal: 6.w),
                      child: Row(
                        children: [
                          Expanded(child: Text(o, style: AppText.bodyStrong())),
                          if (current == o)
                            Icon(PhosphorIconsBold.check, size: 19.sp, color: AppColors.success),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Category options come from `/crm/product-types/` — the org's own list.
  /// The picker used to offer the prototype's fit-out vocabulary, none of which
  /// exists on a live org, and the choice was never sent anyway.
  ///
  /// "Uncategorized" is not a type: it clears `product_type` (§8).
  void _pickCategory() {
    final types = ref.read(productTypeOptionsProvider);
    if (types.isEmpty) {
      // Mock mode (or an org with no types): the built-in list, as before.
      _pick('Category', productCategoryOrder, _cat, (v) => setState(() {
            _cat = v;
            _catId = null;
          }));
      return;
    }
    const none = 'Uncategorized';
    _pick('Category', [none, for (final t in types) t.name],
        _cat.isEmpty ? none : _cat, (v) {
      setState(() {
        if (v == none) {
          _cat = '';
          _catId = null;
          return;
        }
        _cat = v;
        _catId = types.firstWhere((t) => t.name == v).id;
      });
    });
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      ref.read(toastProvider.notifier).show('Enter the product / service name');
      return;
    }
    final price = int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (ApiConfig.apiEnabled) {
      try {
        // Every field the form collects, under the names the serializer uses
        // (`products.md` §3). SKU, category, billing unit and HSN used to be
        // gathered and dropped, and the HSN went out as `hsn_code`, which the
        // backend ignores.
        await ref.read(productsRepositoryProvider).createProduct({
          'product_name': _name.text.trim(),
          // Set once, never changeable afterwards (§4).
          'item_type': widget.isPackage ? 'package' : 'product',
          'product_code': _sku.text.trim(),
          if (_catId != null) 'product_type': _catId,
          'billing_unit': _unit,
          'hsn_sac': _hsn.text.trim(),
          // A package's price is **derived** from its components, and the
          // serializer overwrites whatever is sent (`products.md` §7) — this
          // posted ₹5,00,000 and the row came back ₹0.
          if (!widget.isPackage) 'price': price,
          'tax_rate': _gst,
          'description': _desc.text.trim(),
          'is_active': _forcedInactive ? false : _active,
        });
        if (!mounted) return;
        ref.invalidate(productsProvider);
        Navigator.of(context).pop();
        ref.read(toastProvider.notifier)
            .show('${widget.isPackage ? 'Package' : 'Product'} added to catalog');
      } on AppError catch (e) {
        if (!mounted) return;
        ref.read(toastProvider.notifier).showError(e.message);
      }
      return;
    }
    final id = (_sku.text.trim().isEmpty
            ? '${widget.isPackage ? 'PKG-' : 'NEW-'}${100 + _seq}'
            : _sku.text.trim())
        .toUpperCase();
    final product = Product(
      id: id,
      name: _name.text.trim(),
      kind: widget.isPackage ? 'package' : 'product',
      cat: widget.isPackage ? 'Package' : (_cat.isEmpty ? '' : _cat),
      hsn: _hsn.text.trim().isEmpty ? '—' : _hsn.text.trim(),
      unit: _unit,
      price: _fmtINR(price),
      gst: _gst,
      gstAmt: _fmtINR((price * _gst / 100).round()),
      gross: _fmtINR((price * (1 + _gst / 100)).round()),
      deals: 0,
      revenue: '₹0',
      revNum: 0,
      avg: '—',
      active: _active,
      desc: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
    );
    ref.read(manualProductsProvider.notifier).state = [product, ...ref.read(manualProductsProvider)];
    _seq++;
    Navigator.of(context).pop();
    ref.read(toastProvider.notifier)
        .show('${widget.isPackage ? 'Package' : 'Product'} added to catalog');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
            title: widget.isPackage ? 'Add package' : 'Add product',
            onClose: () => Navigator.of(context).maybePop()),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isPackage) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 5.h),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF3EAFF), borderRadius: BorderRadius.circular(8.r)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsFill.package, size: 13.sp, color: const Color(0xFF890DB6)),
                        SizedBox(width: 6.w),
                        Text('Package / bundle',
                            style: AppText.custom(
                                size: 11.5, weight: FontWeight.w700, color: const Color(0xFF890DB6))),
                      ],
                    ),
                  ),
                  SizedBox(height: 13.h),
                ],
                _field('Product / service name', _name, 'e.g. Reception joinery', required: true),
                SizedBox(height: 14.h),
                Row(
                  children: [
                    Expanded(child: _field('SKU / code', _sku, 'e.g. JN-RECEP')),
                    SizedBox(width: 9.w),
                    Expanded(child: _field('HSN / SAC code', _hsn, 'e.g. 940360')),
                  ],
                ),
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.isPackage) ...[
                      Expanded(
                        child: _picker(
                            'Category', _cat.isEmpty ? 'Uncategorized' : _cat, _pickCategory),
                      ),
                      SizedBox(width: 9.w),
                    ],
                    Expanded(
                      child: _picker('Billing unit', _unit,
                          () => _pick('Billing unit', _unitOptions, _unit, (v) => setState(() => _unit = v))),
                    ),
                  ],
                ),
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 12,
                      child: widget.isPackage
                          ? _derivedPriceField()
                          : _field('Price (₹)', _price, 'e.g. 320000', number: true),
                    ),
                    SizedBox(width: 9.w),
                    Expanded(
                      flex: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label$('GST rate'),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _pick(
                                'GST rate',
                                [for (final r in _gstOptions) '$r%'],
                                '$_gst%',
                                (v) => setState(() =>
                                    _gst = int.parse(v.replaceAll('%', '')))),
                            child: Container(
                            height: 46.h,
                            padding: EdgeInsets.symmetric(horizontal: 14.w),
                            decoration: BoxDecoration(
                                color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$_gst%',
                                    style: AppText.custom(
                                        size: 14, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                                Icon(PhosphorIconsBold.caretDown,
                                    size: 14.sp, color: AppColors.textPlaceholder),
                              ],
                            ),
                          ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
                  decoration:
                      BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(10.r)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(PhosphorIconsRegular.info, size: 15.sp, color: AppColors.blueBright),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                            "Editing a price won't change existing quotes — quotes snapshot product names and prices when generated.",
                            style: AppText.custom(
                                size: 12, weight: FontWeight.w500, color: _bannerText, height: 1.5)),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                _field('Description', _desc, 'What this product or service covers…', multiline: true),
                SizedBox(height: 14.h),
                _label$('Status'),
                Container(
                  padding: EdgeInsets.all(4.w),
                  decoration:
                      BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(12.r)),
                  child: Row(
                    children: [
                      Expanded(
                          child: _statusSeg('Active', !_forcedInactive && _active,
                              _forcedInactive ? null : () => setState(() => _active = true))),
                      SizedBox(width: 6.w),
                      Expanded(
                          child: _statusSeg('Inactive', _forcedInactive || !_active,
                              _forcedInactive ? null : () => setState(() => _active = false))),
                    ],
                  ),
                ),
                // The backend refuses an active package with no components
                // (§7), and this sheet has no component editor — so say that
                // rather than letting the save fail.
                if (_forcedInactive)
                  Padding(
                    padding: EdgeInsets.only(top: 7.h),
                    child: Text(
                        'A package starts inactive — add its components, then activate it.',
                        style: AppText.custom(
                            size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ),
                SizedBox(height: 6.h),
              ],
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _footer() {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 24.h),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _submit,
        child: Container(
          height: 48.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsBold.check, size: 15.sp, color: AppColors.white),
              SizedBox(width: 8.w),
              Text(widget.isPackage ? 'Add package' : 'Add product',
                  style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
            ],
          ),
        ),
      ),
    );
  }

  /// [onTap] is null when the choice is not the user's to make — a package
  /// cannot be created active.
  /// A package has no price of its own: the backend recomputes it from the
  /// components on every write. Asking for one and then discarding it is worse
  /// than not asking.
  Widget _derivedPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label$('Price (₹)'),
        Container(
          height: 46.h,
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
              color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
          child: Row(
            children: [
              Expanded(
                child: Text('From components',
                    style: AppText.custom(
                        size: 14, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ),
              Icon(PhosphorIconsRegular.lockSimple,
                  size: 14.sp, color: AppColors.textPlaceholder),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusSeg(String label, bool on, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 38.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9.r),
        ),
        child: Text(label,
            style: AppText.custom(
                size: 13,
                weight: FontWeight.w700,
                color: on ? AppColors.navy : AppColors.textMuted)),
      ),
    );
  }

  Widget _picker(String label, String value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label$(label),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 46.h,
            padding: EdgeInsets.symmetric(horizontal: 13.w),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(11.r),
              border: Border.all(color: AppColors.borderInput, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(value,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body()),
                ),
                Icon(PhosphorIconsBold.caretDown, size: 12.sp, color: AppColors.textPlaceholder),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, String hint,
      {bool required = false, bool number = false, bool multiline = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label$(label, required: required),
        Container(
          constraints: BoxConstraints(minHeight: multiline ? 84.h : 44.h),
          padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: multiline ? 10.h : 0),
          alignment: multiline ? Alignment.topLeft : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(color: AppColors.borderInput, width: 1.5),
          ),
          child: TextField(
            controller: c,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))] : null,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 5 : 1,
            style: AppText.body(),
            cursorColor: AppColors.blueBright,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: AppText.body(color: AppColors.textPlaceholder),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label$(String text, {bool required = false}) => Padding(
        padding: EdgeInsets.only(bottom: 7.h),
        child: Row(
          children: [
            Text(text,
                style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            if (required)
              Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
          ],
        ),
      );

  /// Indian-grouped rupee display, e.g. 250000 → "₹2,50,000".
  String _fmtINR(int n) {
    final s = n.toString();
    if (s.length <= 3) return '₹$s';
    final last3 = s.substring(s.length - 3);
    // Group the leading part in pairs (Indian numbering).
    final grouped = <String>[];
    var r = s.substring(0, s.length - 3);
    while (r.length > 2) {
      grouped.insert(0, r.substring(r.length - 2));
      r = r.substring(0, r.length - 2);
    }
    if (r.isNotEmpty) grouped.insert(0, r);
    return '₹${grouped.join(',')},$last3';
  }
}
