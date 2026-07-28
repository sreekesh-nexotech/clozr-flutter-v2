import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/products_providers.dart';
import '../../domain/entities/product.dart';

/// New quote — a full-screen form. Line items are chosen from the live product
/// catalog and the total recomputes as you go; submit is a static toast + pop.
class AddQuoteScreen extends ConsumerStatefulWidget {
  const AddQuoteScreen({super.key});

  @override
  ConsumerState<AddQuoteScreen> createState() => _AddQuoteScreenState();
}

class _QuoteLine {
  String productId;
  final TextEditingController qtyCtrl;
  _QuoteLine(this.productId) : qtyCtrl = TextEditingController(text: '1');
}

class _AddQuoteScreenState extends ConsumerState<AddQuoteScreen> {
  final _titleCtrl = TextEditingController();
  final _validCtrl = TextEditingController();
  final _dueCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  final _installmentsCtrl = TextEditingController(text: '2');
  final _billingCtrl = TextEditingController(text: '30');

  final List<_QuoteLine> _lines = [_QuoteLine('')];
  String _template = 'Standard';
  String _payType = 'Lump sum';
  String _owner = 'me';

  static const _templates = ['Standard', 'Compact', 'Detailed'];
  static const _payTypes = ['Lump sum', 'Subscription', 'Installments – even split', 'Installments – custom amounts'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _validCtrl.dispose();
    _dueCtrl.dispose();
    _notesCtrl.dispose();
    _termsCtrl.dispose();
    _installmentsCtrl.dispose();
    _billingCtrl.dispose();
    for (final l in _lines) {
      l.qtyCtrl.dispose();
    }
    super.dispose();
  }

  int _parseAmt(String s) => int.tryParse(s.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  String _fmtAmt(int n) {
    if (n == 0) return '₹0';
    if (n >= 10000000) return '₹${_trim((n / 100000).round() / 100)}Cr';
    if (n >= 100000) return '₹${_trim((n / 10000).round() / 10)}L';
    return '₹${_grouped(n)}';
  }

  String _trim(num v) {
    var s = v.toString();
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  /// Indian digit grouping (3-2-2), e.g. 250000 → 2,50,000.
  String _grouped(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final head = s.substring(0, s.length - 3);
    final tail = s.substring(s.length - 3);
    final buf = StringBuffer();
    for (int i = 0; i < head.length; i++) {
      final fromEnd = head.length - i;
      buf.write(head[i]);
      if (fromEnd > 1 && fromEnd.isOdd) buf.write(',');
    }
    return '$buf,$tail';
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider).valueOrNull ?? const <Product>[];
    final active = products.where((p) => p.active).toList();

    int total = 0;
    for (final line in _lines) {
      final p = _productById(products, line.productId);
      if (p != null) total += _parseAmt(p.price) * (int.tryParse(line.qtyCtrl.text) ?? 1);
    }

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 20.h),
              children: [
                _sectionLabel('Link'),
                AppTextField(
                  label: 'Lead',
                  required: true,
                  readOnly: true,
                  hint: 'Search by name, company or #id',
                  suffixIcon: PhosphorIconsRegular.magnifyingGlass,
                  onTap: () => ref.read(toastProvider.notifier).show('Lead search — coming soon'),
                ),
                SizedBox(height: 6.h),
                Row(
                  children: [
                    Icon(PhosphorIconsRegular.magnifyingGlass, size: 14.sp, color: AppColors.textPlaceholder),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text('No matching lead yet — search by name, company or #id',
                          style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                    ),
                  ],
                ),
                SizedBox(height: 14.h),
                AppTextField(label: 'Quote title', controller: _titleCtrl, hint: 'e.g. Showroom fit-out — phase 2'),
                SizedBox(height: 14.h),
                _chipField(
                  label: 'Template',
                  required: true,
                  options: _templates,
                  selected: _template,
                  onSelect: (v) => setState(() => _template = v),
                ),
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'Owner',
                        readOnly: true,
                        value: MockUsers.of(_owner).name,
                        onTap: _pickOwner,
                      ),
                    ),
                    SizedBox(width: 9.w),
                    Expanded(child: _currencyField()),
                  ],
                ),
                SizedBox(height: 22.h),
                _sectionLabel('Line items · from product catalog'),
                for (int i = 0; i < _lines.length; i++) ...[
                  if (i > 0) SizedBox(height: 10.h),
                  _lineItem(i, products, active),
                ],
                SizedBox(height: 10.h),
                GestureDetector(
                  onTap: () => setState(() => _lines.add(_QuoteLine(''))),
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: AppColors.borderInput, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.plus, size: 14.sp, color: AppColors.textLabelAlt),
                        SizedBox(width: 7.w),
                        Text('Add product line', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('Quote total', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                    SizedBox(width: 10.w),
                    Text(_fmtAmt(total), style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
                  ],
                ),
                SizedBox(height: 2.h),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('Tax-free — product amounts only',
                      style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                ),
                SizedBox(height: 22.h),
                _sectionLabel('Payment & validity'),
                _chipField(
                  label: 'Payment type',
                  required: true,
                  options: _payTypes,
                  selected: _payType,
                  onSelect: (v) => setState(() => _payType = v),
                ),
                if (_payType.contains('even split')) ...[
                  SizedBox(height: 14.h),
                  AppTextField(label: 'Number of installments (min 2)', controller: _installmentsCtrl, hint: 'e.g. 3', keyboardType: TextInputType.number),
                ],
                if (_payType != 'Lump sum') ...[
                  SizedBox(height: 14.h),
                  AppTextField(label: 'Billing period (days)', controller: _billingCtrl, hint: 'e.g. 30', keyboardType: TextInputType.number),
                ],
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: AppTextField(label: 'Valid until', controller: _validCtrl, hint: 'e.g. 18 Jul 2026')),
                    SizedBox(width: 9.w),
                    Expanded(child: AppTextField(label: 'Due date', controller: _dueCtrl, hint: 'e.g. 25 Jul 2026')),
                  ],
                ),
                SizedBox(height: 14.h),
                AppTextField(label: 'Notes', controller: _notesCtrl, multiline: true, hint: 'Notes shown on the quote…'),
                SizedBox(height: 14.h),
                AppTextField(label: 'Terms & conditions', controller: _termsCtrl, multiline: true, hint: 'The T&C text printed on the quote…'),
              ],
            ),
          ),
          _actionBar(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 14.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.pop(),
            child: Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: const Color(0xFFE6E7EA)),
              ),
              child: Icon(PhosphorIconsBold.caretLeft, size: 17.sp, color: AppColors.textBody),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New quote', style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                Text('Line items come from the product catalog',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2.w, 14.h, 2.w, 12.h),
      child: Text(text.toUpperCase(),
          style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
    );
  }

  Widget _chipField({
    required String label,
    required bool required,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            if (required)
              Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
          ],
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final o in options)
              GestureDetector(
                onTap: () => onSelect(o),
                child: Container(
                  height: 38.h,
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == o ? AppColors.blueSubtle : AppColors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: selected == o ? const Color(0xFFA6D1FF) : const Color(0xFFE6E7EA),
                      width: selected == o ? 1.5 : 1,
                    ),
                  ),
                  child: Text(o,
                      style: AppText.custom(
                          size: 13,
                          weight: selected == o ? FontWeight.w700 : FontWeight.w600,
                          color: selected == o ? AppColors.navy : AppColors.textLabelAlt)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _currencyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Currency', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
        SizedBox(height: 7.h),
        Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 13.w),
          decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
          child: Row(
            children: [
              Expanded(
                child: Text('INR — Indian Rupee (₹)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              ),
              Icon(PhosphorIconsRegular.lockSimple, size: 14.sp, color: AppColors.textPlaceholder),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lineItem(int index, List<Product> all, List<Product> active) {
    final line = _lines[index];
    final selected = _productById(all, line.productId);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(13.r),
        border: Border.all(color: const Color(0xFFE6E7EA)),
      ),
      child: Column(
        children: [
          Container(
            height: 44.h,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11.r),
              border: Border.all(color: AppColors.borderInput, width: 1.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: line.productId.isEmpty ? '' : line.productId,
                isExpanded: true,
                icon: Icon(PhosphorIconsBold.caretDown, size: 12.sp, color: AppColors.textMuted2),
                style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text('Select product…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ),
                  for (final p in active)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.name} — ${p.price}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
                    ),
                ],
                onChanged: (v) => setState(() => line.productId = v ?? ''),
              ),
            ),
          ),
          SizedBox(height: 9.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 74.w,
                height: 44.h,
                child: Container(
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11.r),
                    border: Border.all(color: AppColors.borderInput, width: 1.5),
                  ),
                  child: TextField(
                    controller: line.qtyCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody),
                    cursorColor: AppColors.blueBright,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Qty',
                      hintStyle: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 9.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unit price', style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                    Text(selected != null ? '${selected.price} ${selected.unit}' : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Line total', style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  Text(
                    selected != null ? _fmtAmt(_parseAmt(selected.price) * (int.tryParse(line.qtyCtrl.text) ?? 1)) : '₹0',
                    style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ],
              ),
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: () => setState(() {
                  if (_lines.length > 1) {
                    _lines.removeAt(index).qtyCtrl.dispose();
                  }
                }),
                child: Container(
                  width: 32.w,
                  height: 32.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9.r),
                    border: Border.all(color: const Color(0xFFF3C1C1)),
                  ),
                  child: Icon(PhosphorIconsRegular.trash, size: 15.sp, color: AppColors.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 100.w,
              height: 48.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFE6E7EA)),
              ),
              child: Text('Cancel', style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              onTap: () {
                ref.read(toastProvider.notifier).show('Quote created');
                context.pop();
              },
              child: Container(
                height: 48.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.white),
                    SizedBox(width: 8.w),
                    Text('Create quote', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickOwner() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OwnerSheet(current: _owner),
    );
    if (chosen != null) setState(() => _owner = chosen);
  }

  Product? _productById(List<Product> products, String id) {
    if (id.isEmpty) return null;
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Minimal owner picker sheet reusing the sheet chrome.
class _OwnerSheet extends StatelessWidget {
  const _OwnerSheet({required this.current});
  final String current;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgApp,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 10.h, bottom: 8.h),
              child: Container(
                width: 38.w,
                height: 5.h,
                decoration: BoxDecoration(color: AppColors.borderGrey, borderRadius: BorderRadius.circular(3.r)),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 8.h),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Owner', style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
            ),
            for (final r in MockUsers.reps)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(r.id),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 13.h),
                  child: Row(
                    children: [
                      Container(
                        width: 38.w,
                        height: 38.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
                        child: Text(r.initials, style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.white)),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name, style: AppText.custom(size: 14.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
                            Text(r.role, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      if (r.id == current) Icon(PhosphorIconsBold.check, size: 18.sp, color: AppColors.success),
                    ],
                  ),
                ),
              ),
            SizedBox(height: 12.h),
          ],
        ),
      ),
    );
  }
}
