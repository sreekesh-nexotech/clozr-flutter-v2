import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../../core/widgets/primary_button.dart';
import '../../../application/customer_detail_rules.dart';
import '../../../domain/entities/crm_catalog.dart';
import '../option_picker_sheet.dart';
import 'customer_field_editor.dart' show CustomerFieldSave;

/// The webapp's "Products" dialog (`LeadProductsModal` titled Products) for a
/// customer: each product with a whole-number quantity. Saves
/// `PATCH {products: [{product_id, quantity}]}`.
Future<void> showCustomerProductsSheet(
  BuildContext context, {
  required Object? current,
  required List<CatalogOption> options,
  required CustomerFieldSave onSave,
}) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _ProductsSheet(current: customerProductRows(current), options: options, onSave: onSave),
  );
}

class _Row {
  _Row(this.id, this.label, String qty) : qty = TextEditingController(text: qty);
  final String id;
  final String label;
  final TextEditingController qty;
}

class _ProductsSheet extends StatefulWidget {
  const _ProductsSheet({required this.current, required this.options, required this.onSave});

  final List<({String id, String label, String quantity})> current;
  final List<CatalogOption> options;
  final CustomerFieldSave onSave;

  @override
  State<_ProductsSheet> createState() => _ProductsSheetState();
}

class _ProductsSheetState extends State<_ProductsSheet> {
  late final List<_Row> _rows = [for (final r in widget.current) _Row(r.id, r.label, r.quantity)];
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _add() async {
    final taken = {for (final r in _rows) r.id};
    final picked = await showOptionPicker(
      context: context,
      title: 'Add product',
      options: [for (final o in widget.options) if (!taken.contains(o.id)) o],
      selected: const {},
      emptyNote: 'No more products to add.',
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final o = widget.options.firstWhere((o) => o.id == picked.first);
    setState(() => _rows.add(_Row(o.id, o.name, '1')));
  }

  Future<void> _save() async {
    final body = customerProductsPatch([for (final r in _rows) (productId: r.id, quantity: r.qty.text)]);
    if (body.error != null) {
      setState(() => _error = body.error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await widget.onSave({'products': body.value});
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = err.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Products'),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_rows.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Text('No products yet.', style: AppText.caption(color: AppColors.textMuted)),
                    ),
                  for (final r in _rows)
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(r.label,
                                style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                          ),
                          SizedBox(
                            width: 70.w,
                            child: TextField(
                              controller: r.qty,
                              textAlign: TextAlign.center,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: 'Qty',
                                contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                              ),
                              onChanged: (_) => _error == null ? null : setState(() => _error = null),
                            ),
                          ),
                          IconButton(
                            icon: Icon(PhosphorIconsBold.x, size: 15.sp, color: AppColors.textMuted),
                            onPressed: () => setState(() {
                              r.qty.dispose();
                              _rows.remove(r);
                            }),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 8.h),
                  TextButton.icon(
                    onPressed: _add,
                    icon: Icon(PhosphorIconsRegular.plus, size: 15.sp),
                    label: const Text('Add product'),
                  ),
                  if (_error != null)
                    Text(_error!, style: AppText.caption(color: AppColors.error)),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
            child: Row(
              children: [
                Expanded(child: PrimaryButton(label: 'Cancel', ghost: true, onTap: () => Navigator.of(context).pop())),
                SizedBox(width: 10.w),
                Expanded(flex: 2, child: PrimaryButton(label: _saving ? 'Saving…' : 'Save', onTap: _saving ? null : _save)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
