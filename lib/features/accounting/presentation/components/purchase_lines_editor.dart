import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../config/accounting_copy.dart';
import 'acc_widgets.dart';

/// One line of a purchase form (vendor bill / expense). The form rows are
/// `{description, hsn_sac (≤8), supply_nature, qty, unit_price, …}` — here a
/// line is one amount with qty 1, which is how a field expense is entered.
class PurchaseLineDraft {
  PurchaseLineDraft();

  final description = TextEditingController();
  final amount = TextEditingController();
  final hsn = TextEditingController();
  String nature = 'SERVICE';

  void dispose() {
    description.dispose();
    amount.dispose();
    hsn.dispose();
  }

  bool get hsnValid => hsn.text.trim().isEmpty || RegExp(r'^\d{4,8}$').hasMatch(hsn.text.trim());

  bool get complete => description.text.trim().isNotEmpty && moneyInput(amount.text) != null && !moneyIsZero(moneyInput(amount.text));

  Map<String, Object?> toJson() => {
        'description': description.text.trim(),
        if (hsn.text.trim().isNotEmpty) 'hsn_sac': hsn.text.trim(),
        'supply_nature': nature,
        'qty': '1',
        'unit_price': moneyInput(amount.text),
      };
}

/// The sum of the lines' amounts — a hint for the confirm step only; tax,
/// TDS and the payable are the server's (handover §12.9).
String purchaseLinesHint(List<PurchaseLineDraft> lines) =>
    toMoneyStr(lines.fold(0.0, (s, l) => s + moneyNum(moneyInput(l.amount.text))));

/// Editable list of purchase lines with an "Add line" control.
class PurchaseLinesEditor extends StatelessWidget {
  const PurchaseLinesEditor({super.key, required this.lines, required this.onChanged});

  final List<PurchaseLineDraft> lines;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < lines.length; i++) ...[
          if (i > 0) SizedBox(height: 10.h),
          _line(i),
        ],
        SizedBox(height: 8.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            lines.add(PurchaseLineDraft());
            onChanged();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6.h),
            child: Row(
              children: [
                Icon(PhosphorIconsBold.plus, size: 13.sp, color: AppColors.blueBright),
                SizedBox(width: 6.w),
                Text('Add line', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _line(int i) {
    final l = lines[i];
    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Line ${i + 1}',
                    style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textMuted)),
              ),
              if (lines.length > 1)
                GestureDetector(
                  onTap: () {
                    lines.removeAt(i).dispose();
                    onChanged();
                  },
                  child: Icon(PhosphorIconsRegular.trash, size: 17.sp, color: AppColors.error),
                ),
            ],
          ),
          SizedBox(height: 8.h),
          AccInput(
            label: 'Description',
            required: true,
            controller: l.description,
            hint: 'What was bought',
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => onChanged(),
          ),
          SizedBox(height: 10.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MoneyField(label: 'Amount', required: true, controller: l.amount, onChanged: (_) => onChanged())),
              SizedBox(width: 9.w),
              Expanded(
                child: AccInput(
                  label: 'HSN / SAC',
                  controller: l.hsn,
                  hint: 'Optional',
                  errorText: l.hsnValid ? null : '4 to 8 digits',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          AccChoiceChips(
            options: supplyNatureLabels,
            selected: l.nature,
            onSelected: (v) {
              l.nature = v;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}
