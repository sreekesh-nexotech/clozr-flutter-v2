import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/domain/entities/acc_masters.dart';
import '../../application/customer_form_rules.dart';
import '../../domain/entities/crm_catalog.dart';
import 'option_picker_sheet.dart';

/// State of the billing / delivery address and GSTIN block (webapp
/// `CustomerAddressFields`): one controller per input, "Same as billing
/// address", and the server's message per input.
class CustomerAddressController extends ChangeNotifier {
  CustomerAddressController({Map<String, dynamic>? row})
      : sameAsBilling = deliveryMatchesBilling(row) {
    final seed = addressValuesFromRow(row);
    for (final spec in allAddressFields) {
      _text[spec.name] = TextEditingController(text: seed[spec.name]);
    }
  }

  final Map<String, TextEditingController> _text = {};
  final Map<String, GlobalKey> _keys = {
    for (final spec in allAddressFields) spec.name: GlobalKey(),
  };

  bool sameAsBilling;
  Map<String, String> _errors = const {};

  TextEditingController controller(String name) => _text[name]!;
  GlobalKey keyOf(String name) => _keys[name]!;
  String? errorOf(String name) => _errors[name];
  bool get hasErrors => _errors.isNotEmpty;

  Map<String, String> get values => {for (final e in _text.entries) e.key: e.value.text};

  /// The block's part of a create body.
  Map<String, String> get createPayload =>
      customerAddressPayload(values, sameAsBilling: sameAsBilling);

  /// The block's part of a PATCH against [row].
  Map<String, String?> patchAgainst(Map<String, dynamic>? row) =>
      customerAddressPatch(values, row, sameAsBilling: sameAsBilling);

  void setSameAsBilling(bool same) {
    sameAsBilling = same;
    notifyListeners();
  }

  void setValue(String name, String value) {
    _text[name]!.text = value;
    clearError(name);
    notifyListeners();
  }

  void clearError(String name) {
    if (!_errors.containsKey(name)) return;
    _errors = {..._errors}..remove(name);
    notifyListeners();
  }

  /// Takes the server's errors (API key → message) that belong to this block
  /// and returns the keys it placed.
  Set<String> showServerErrors(Map<String, String> errors) {
    final placed = <String>{};
    final next = <String, String>{};
    for (final e in errors.entries) {
      final field = addressErrorField(e.key, sameAsBilling: sameAsBilling);
      if (field == null) continue;
      next.putIfAbsent(field, () => e.value);
      placed.add(e.key);
    }
    _errors = next;
    notifyListeners();
    return placed;
  }

  void clearErrors() {
    if (_errors.isEmpty) return;
    _errors = const {};
    notifyListeners();
  }

  /// Brings the first input carrying an error into view.
  void scrollToFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final spec in allAddressFields) {
        if (!_errors.containsKey(spec.name)) continue;
        final ctx = _keys[spec.name]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 250));
        }
        return;
      }
    });
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// The Billing address / Delivery address / Tax sections of the customer
/// forms, in the sheet's own field style.
class CustomerAddressFields extends ConsumerWidget {
  const CustomerAddressFields({super.key, required this.controller});

  final CustomerAddressController controller;

  static const _none = '__none__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(gstStatesProvider).valueOrNull ?? const [];
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        Widget field(AddressFieldSpec spec) => KeyedSubtree(
              key: controller.keyOf(spec.name),
              child: _input(context, spec, states),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FormSection(
              title: 'Billing address',
              children: [for (final spec in billingAddressFields) field(spec)],
            ),
            SizedBox(height: 18.h),
            FormSection(
              title: 'Delivery address',
              children: [
                _sameToggle(),
                if (!controller.sameAsBilling)
                  for (final spec in deliveryAddressFields) field(spec),
              ],
            ),
            SizedBox(height: 18.h),
            FormSection(
              title: 'Tax',
              gap: 6,
              children: [
                field(gstinField),
                Padding(
                  padding: EdgeInsets.only(left: 2.w),
                  child: Text(gstinHint, style: AppText.caption()),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _sameToggle() {
    final same = controller.sameAsBilling;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => controller.setSameAsBilling(!same),
      child: Row(
        children: [
          Icon(same ? PhosphorIconsFill.checkSquare : PhosphorIconsRegular.square,
              size: 18.sp, color: same ? AppColors.navy : AppColors.textMuted),
          SizedBox(width: 8.w),
          Text('Same as billing address', style: AppText.bodyStrong()),
        ],
      ),
    );
  }

  Widget _input(BuildContext context, AddressFieldSpec spec, List<GstState> states) {
    final ctrl = controller.controller(spec.name);
    final error = controller.errorOf(spec.name);
    switch (spec.kind) {
      case 'state':
        final code = ctrl.text.trim();
        String display = code;
        for (final st in states) {
          if (st.code == code) display = '${st.name} (${st.code})';
        }
        return AppTextField(
          label: spec.label,
          readOnly: true,
          value: display,
          hint: states.isEmpty ? 'Loading states…' : 'Select a state',
          suffixIcon: PhosphorIconsRegular.caretDown,
          errorText: error,
          onTap: () => _pickState(context, spec, states),
        );
      case 'pincode':
        return AppTextField(
          label: spec.label,
          controller: ctrl,
          hint: 'e.g. 682001',
          errorText: error,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          onChanged: (_) => controller.clearError(spec.name),
        );
      case 'gstin':
        return AppTextField(
          label: spec.label,
          controller: ctrl,
          hint: 'e.g. 32ABCDE1234F1Z5',
          errorText: error,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
            const _UpperCaseFormatter(),
            LengthLimitingTextInputFormatter(15),
          ],
          onChanged: (_) => controller.clearError(spec.name),
        );
      default:
        return AppTextField(
          label: spec.label,
          controller: ctrl,
          hint: 'Enter ${spec.label.toLowerCase()}…',
          errorText: error,
          onChanged: (_) => controller.clearError(spec.name),
        );
    }
  }

  Future<void> _pickState(BuildContext context, AddressFieldSpec spec, List<GstState> states) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showOptionPicker(
      context: context,
      title: spec.label,
      options: [
        const CatalogOption(id: _none, name: '—'),
        for (final st in states) CatalogOption(id: st.code, name: '${st.name} (${st.code})'),
      ],
      selected: {controller.controller(spec.name).text.trim()},
      emptyNote: 'Loading states…',
    );
    if (picked == null || picked.isEmpty) return;
    controller.setValue(spec.name, picked.first == _none ? '' : picked.first);
  }
}

/// GSTIN is typed in capitals, as the webapp forces it.
class _UpperCaseFormatter extends TextInputFormatter {
  const _UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
