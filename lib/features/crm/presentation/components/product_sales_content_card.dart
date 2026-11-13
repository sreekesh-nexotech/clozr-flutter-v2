import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/utils/attachment_link.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/product_sales_content.dart';
import '../../application/providers/products_providers.dart';
import '../../domain/entities/product.dart';
import 'finance_widgets.dart';

/// Product detail › "Sales content" (the webapp's card): features, specifications,
/// warranty, delivery lead time, images and a brochure, printed on proposals and
/// generated documents. Whoever may update the product can edit the text parts;
/// images and the brochure come from the media library on the web and are shown here.
class ProductSalesContentCard extends ConsumerWidget {
  const ProductSalesContentCard(
      {super.key, required this.product, required this.canEdit});
  final Product product;
  final bool canEdit;

  Widget _eyebrow(String t) => Text(t.toUpperCase(),
      style: AppText.custom(
          size: 11, weight: FontWeight.w600, color: AppColors.textMuted));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SalesContent.fromRaw(product.raw);
    final body = c.isEmpty
        ? Text(
            'No features, specifications, images or brochure yet.${canEdit ? ' Add them so proposals can show this product properly.' : ''}',
            style: AppText.caption())
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (c.images.isNotEmpty) ...[
              Wrap(spacing: 8.w, runSpacing: 8.h, children: [
                for (final i in c.images)
                  GestureDetector(
                    onTap: i.url.isEmpty ? null : () => openAttachment(i.url),
                    child: Container(
                      padding: EdgeInsets.all(3.r),
                      decoration: BoxDecoration(
                          border: Border.all(color: AppColors.borderCardSoft),
                          borderRadius: BorderRadius.circular(10.r)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: Image.network(i.url,
                            width: 64.w,
                            height: 64.w,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => SizedBox(
                                width: 64.w,
                                height: 64.w,
                                child: Icon(PhosphorIconsRegular.image,
                                    color: AppColors.textPlaceholder))),
                      ),
                    ),
                  ),
              ]),
              SizedBox(height: 14.h),
            ],
            if (c.features.isNotEmpty) ...[
              _eyebrow('Features'),
              SizedBox(height: 6.h),
              for (final f in c.features)
                Padding(
                  padding: EdgeInsets.only(bottom: 3.h),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: AppText.body()),
                        Expanded(child: Text(f, style: AppText.body())),
                      ]),
                ),
              SizedBox(height: 11.h),
            ],
            if (c.specs.isNotEmpty) ...[
              _eyebrow('Specifications'),
              SizedBox(height: 4.h),
              for (var i = 0; i < c.specs.length; i++)
                Container(
                  decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : const Border(
                              top:
                                  BorderSide(color: AppColors.borderCardSoft))),
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(c.specs[i].label,
                                style: AppText.caption())),
                        SizedBox(width: 12.w),
                        Flexible(
                          child: Text(
                              c.specs[i].value.isEmpty ? '—' : c.specs[i].value,
                              textAlign: TextAlign.right,
                              style: AppText.custom(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                      ]),
                ),
              SizedBox(height: 11.h),
            ],
            if (c.warranty.isNotEmpty) ...[
              _eyebrow('Warranty'),
              SizedBox(height: 4.h),
              Text(c.warranty, style: AppText.body()),
              SizedBox(height: 11.h),
            ],
            if (c.leadTimeLabel.isNotEmpty) ...[
              _eyebrow('Delivery lead time'),
              SizedBox(height: 4.h),
              Text(c.leadTimeLabel, style: AppText.body()),
              SizedBox(height: 11.h),
            ],
            if (c.brochure != null)
              GestureDetector(
                onTap: c.brochure!.url.isEmpty
                    ? null
                    : () => openAttachment(c.brochure!.url),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(PhosphorIconsRegular.filePdf,
                      size: 18.sp, color: AppColors.error),
                  SizedBox(width: 8.w),
                  Flexible(
                    child: Text(
                        '${c.brochure!.name.isEmpty ? 'Brochure' : c.brochure!.name} (PDF)',
                        style: AppText.custom(
                            size: 13.5,
                            weight: FontWeight.w600,
                            color: AppColors.navy)),
                  ),
                ]),
              ),
          ]);
    return FinanceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Text('Sales content',
                  style: AppText.custom(
                      size: 16,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              SizedBox(width: 6.w),
              Tooltip(
                message: 'Printed on proposals and generated documents.',
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(PhosphorIconsRegular.info,
                    size: 15.sp, color: AppColors.textPlaceholder),
              ),
            ]),
          ),
          if (canEdit)
            GestureDetector(
              onTap: () => _edit(context, ref, c),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderCardSoft),
                    borderRadius: BorderRadius.circular(10.r)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(PhosphorIconsRegular.pencilSimple,
                      size: 14.sp, color: AppColors.navy),
                  SizedBox(width: 5.w),
                  Text('Edit',
                      style: AppText.custom(
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: AppColors.navy)),
                ]),
              ),
            ),
        ]),
        SizedBox(height: 12.h),
        body,
      ]),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, SalesContent saved) async {
    final patch = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ContentEditor(product: product, saved: saved),
    );
    if (patch == null || patch.isEmpty) return;
    final toast = ref.read(toastProvider.notifier);
    try {
      await ref
          .read(productsRepositoryProvider)
          .updateProduct(product.id, patch);
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      toast.showError(e.bareMessage);
      return;
    }
    ref.invalidate(productDetailProvider(product.id));
    ref.invalidate(productsProvider);
    toast.show('Sales content saved');
  }
}

class _ContentEditor extends StatefulWidget {
  const _ContentEditor({required this.product, required this.saved});
  final Product product;
  final SalesContent saved;

  @override
  State<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends State<_ContentEditor> {
  late final ContentDraft _d = ContentDraft.from(widget.saved);
  final List<TextEditingController> _feat = [];
  final List<(TextEditingController, TextEditingController)> _spec = [];
  late final _warranty = TextEditingController(text: _d.warranty);
  late final _days = TextEditingController(text: _d.leadDays);
  late final _note = TextEditingController(text: _d.leadNote);
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    for (final f in _d.features) {
      _feat.add(TextEditingController(text: f));
    }
    for (final s in _d.specs) {
      _spec.add((
        TextEditingController(text: s.label),
        TextEditingController(text: s.value)
      ));
    }
  }

  @override
  void dispose() {
    for (final c in _feat) {
      c.dispose();
    }
    for (final s in _spec) {
      s.$1.dispose();
      s.$2.dispose();
    }
    _warranty.dispose();
    _days.dispose();
    _note.dispose();
    super.dispose();
  }

  ContentDraft get _current => ContentDraft(
        features: [for (final c in _feat) c.text],
        specs: [for (final s in _spec) (label: s.$1.text, value: s.$2.text)],
        warranty: _warranty.text,
        leadDays: _days.text,
        leadNote: _note.text,
      );

  void _save() {
    setState(() => _attempted = true);
    final d = _current;
    if (contentProblems(d).isNotEmpty) return;
    Navigator.of(context).pop(contentPatch(widget.saved, d));
  }

  Widget _label(String t) => Padding(
        padding: EdgeInsets.only(top: 14.h, bottom: 6.h),
        child: Text(t,
            style: AppText.custom(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.textPrimary)),
      );

  Widget _err(String? e) => e == null
      ? const SizedBox.shrink()
      : Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: Text(e, style: AppText.caption(color: AppColors.error)));

  InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint, isDense: true, border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    final problems =
        _attempted ? contentProblems(_current) : <String, String>{};
    return AlertDialog(
      title: Text('Sales content — ${widget.product.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Features'),
            for (var i = 0; i < _feat.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _feat[i],
                          maxLength: kContentFeatureChars,
                          buildCounter: (_,
                                  {required currentLength,
                                  required isFocused,
                                  maxLength}) =>
                              null,
                          decoration: _dec('e.g. Reads 1D and 2D barcodes'))),
                  IconButton(
                      tooltip: 'Remove feature ${i + 1}',
                      onPressed: () => setState(() {
                            _feat.removeAt(i).dispose();
                          }),
                      icon: const Icon(Icons.close, size: 18)),
                ]),
              ),
            if (_feat.length < kContentMaxFeatures)
              TextButton.icon(
                  onPressed: () =>
                      setState(() => _feat.add(TextEditingController())),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add feature')),
            _err(problems['features']),
            _label('Specifications'),
            for (var i = 0; i < _spec.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _spec[i].$1,
                          decoration: _dec('Label, e.g. Weight'))),
                  SizedBox(width: 8.w),
                  Expanded(
                      flex: 2,
                      child: TextField(
                          controller: _spec[i].$2,
                          decoration: _dec('Value, e.g. 180 g'))),
                  IconButton(
                      tooltip: 'Remove specification ${i + 1}',
                      onPressed: () => setState(() {
                            final s = _spec.removeAt(i);
                            s.$1.dispose();
                            s.$2.dispose();
                          }),
                      icon: const Icon(Icons.close, size: 18)),
                ]),
              ),
            if (_spec.length < kContentMaxSpecs)
              TextButton.icon(
                  onPressed: () => setState(() => _spec
                      .add((TextEditingController(), TextEditingController()))),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add specification')),
            _err(problems['specs']),
            _label('Warranty summary'),
            TextField(
                controller: _warranty,
                minLines: 2,
                maxLines: 4,
                decoration: _dec(
                    'e.g. 1 year onsite warranty against manufacturing defects')),
            _err(problems['warranty']),
            _label('Delivery lead time (days)'),
            TextField(
                controller: _days,
                keyboardType: TextInputType.number,
                decoration: _dec('e.g. 14')),
            _err(problems['leadDays']),
            _label('Lead time note'),
            TextField(
                controller: _note,
                decoration: _dec('e.g. after advance payment')),
            _err(problems['leadNote']),
            if (widget.saved.images.isNotEmpty || widget.saved.brochure != null)
              Padding(
                padding: EdgeInsets.only(top: 14.h),
                child: Text(
                    'Images and the brochure are managed from the media library on the web app and are kept as they are.',
                    style: AppText.caption()),
              ),
            if (_attempted && problems.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 10.h),
                child: Text('Fix the highlighted fields.',
                    style: AppText.caption(color: AppColors.error)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
