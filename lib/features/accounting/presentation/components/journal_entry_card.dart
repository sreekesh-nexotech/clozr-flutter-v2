import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../domain/entities/acc_ledger.dart';
import '../config/accounting_copy.dart';

/// One posted journal entry: its number and date, then each line with its
/// account and the debit or credit side. Read-only.
class JournalEntryCard extends StatelessWidget {
  const JournalEntryCard({super.key, required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Entry ${entry.entryNo ?? ''}'.trim(),
                    style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              Text(formatApiDay(entry.postingDate),
                  style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
          ),
          if ((entry.narration ?? '').isNotEmpty || entry.eventType != null) ...[
            SizedBox(height: 3.h),
            Text(entry.narration ?? label(const {}, entry.eventType),
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
          ],
          if (entry.reversedByEntryId != null) ...[
            SizedBox(height: 4.h),
            Text('Reversed', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
          ],
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(child: Text('Account', style: _head)),
              SizedBox(width: 76.w, child: Text('Debit', textAlign: TextAlign.right, style: _head)),
              SizedBox(width: 76.w, child: Text('Credit', textAlign: TextAlign.right, style: _head)),
            ],
          ),
          for (final l in entry.lines)
            Container(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF3F4F5)))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      [if (l.accountCode != null) l.accountCode!, if (l.role != null) label(const {}, l.role)].join(' · '),
                      style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textBody),
                    ),
                  ),
                  SizedBox(width: 76.w, child: Text(moneyIsZero(l.debit) ? '' : formatMoneyStr(l.debit), textAlign: TextAlign.right, style: _num)),
                  SizedBox(width: 76.w, child: Text(moneyIsZero(l.credit) ? '' : formatMoneyStr(l.credit), textAlign: TextAlign.right, style: _num)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static TextStyle get _head => AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4);
  static TextStyle get _num => AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textPrimary);
}
