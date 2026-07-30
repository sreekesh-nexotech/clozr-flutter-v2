import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
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

  String _cat = 'Fit-out';
  String _unit = 'per sq.ft.';
  bool _active = true;
  int _seq = 1;

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

  void _submit() {
    if (_name.text.trim().isEmpty) {
      ref.read(toastProvider.notifier).show('Enter the product / service name');
      return;
    }
    final price = int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final id = (_sku.text.trim().isEmpty
            ? '${widget.isPackage ? 'PKG-' : 'NEW-'}${100 + _seq}'
            : _sku.text.trim())
        .toUpperCase();
    final product = Product(
      id: id,
      name: _name.text.trim(),
      kind: widget.isPackage ? 'package' : 'product',
      cat: widget.isPackage ? 'Package' : _cat,
      hsn: _hsn.text.trim().isEmpty ? '—' : _hsn.text.trim(),
      unit: _unit,
      price: _fmtINR(price),
      gst: 18,
      gstAmt: _fmtINR((price * 0.18).round()),
      gross: _fmtINR((price * 1.18).round()),
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
                        child: _picker('Category', _cat,
                            () => _pick('Category', productCategoryOrder, _cat, (v) => setState(() => _cat = v))),
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
                    Expanded(flex: 12, child: _field('Price (₹)', _price, 'e.g. 320000', number: true)),
                    SizedBox(width: 9.w),
                    Expanded(
                      flex: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label$('GST rate'),
                          Container(
                            height: 46.h,
                            padding: EdgeInsets.symmetric(horizontal: 14.w),
                            decoration: BoxDecoration(
                                color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('18%',
                                    style: AppText.custom(
                                        size: 14, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                                Icon(PhosphorIconsRegular.lockSimple,
                                    size: 14.sp, color: AppColors.textPlaceholder),
                              ],
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
                      Expanded(child: _statusSeg('Active', _active, () => setState(() => _active = true))),
                      SizedBox(width: 6.w),
                      Expanded(child: _statusSeg('Inactive', !_active, () => setState(() => _active = false))),
                    ],
                  ),
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

  Widget _statusSeg(String label, bool on, VoidCallback onTap) {
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
