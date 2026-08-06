import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/search_field.dart';
import '../../domain/entities/lead.dart';

/// Picks a lead — the required link on a new quote.
///
/// Searches the leads already loaded rather than querying: the list is in
/// memory, the set is bounded by the same page walk the Leads screen does, and
/// a keystroke-per-request picker would be worse on a phone.
Future<Lead?> showLeadPickerSheet({
  required BuildContext context,
  required List<Lead> leads,
}) {
  return showClozrSheet<Lead>(
    context: context,
    builder: (_) => _LeadPickerSheet(leads: leads),
  );
}

class _LeadPickerSheet extends StatefulWidget {
  const _LeadPickerSheet({required this.leads});

  final List<Lead> leads;

  @override
  State<_LeadPickerSheet> createState() => _LeadPickerSheetState();
}

class _LeadPickerSheetState extends State<_LeadPickerSheet> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Lead> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.leads;
    return [
      for (final l in widget.leads)
        if (l.name.toLowerCase().contains(q) ||
            (l.company ?? '').toLowerCase().contains(q) ||
            l.id.toLowerCase().contains(q))
          l,
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
          Text('Select lead',
              style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
          SizedBox(height: 12.h),
          SearchField(
            controller: _ctrl,
            hint: 'Search by name, company or #id',
            onChanged: (v) => setState(() => _query = v),
            onClose: () {
              _ctrl.clear();
              setState(() => _query = '');
            },
          ),
          SizedBox(height: 10.h),
          Flexible(
            child: matches.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 28.h),
                    child: Center(
                      child: Text('No matching lead',
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

  Widget _row(Lead lead) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(lead),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        child: Row(
          children: [
            Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1F4),
                borderRadius: BorderRadius.circular(11.r),
              ),
              child: Text(lead.initials,
                  style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lead.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text('${lead.company ?? '—'} · #${lead.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                ],
              ),
            ),
            Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
          ],
        ),
      ),
    );
  }
}

/// A hairline between picker rows.
class ClozrDividerLine extends StatelessWidget {
  const ClozrDividerLine({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: const Color(0xFFF3F4F5));
}
