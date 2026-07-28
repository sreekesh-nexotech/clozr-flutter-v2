import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/entities/ops_task.dart';

/// One entry in an audit-log timeline.
class AuditEntry {
  final IconData icon;
  final Color tone;
  final Color bg;
  final String title;
  final String sub;
  const AuditEntry({required this.icon, required this.tone, required this.bg, required this.title, required this.sub});
}

String opsInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

/// The "Audit log" card with an icon-dot timeline.
class OpsAuditLog extends StatelessWidget {
  const OpsAuditLog({super.key, required this.entries});
  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.clockCounterClockwise, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Audit log', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          for (int i = 0; i < entries.length; i++) _row(entries[i], i < entries.length - 1),
        ],
      ),
    );
  }

  Widget _row(AuditEntry a, bool hasLine) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: a.bg, shape: BoxShape.circle),
                child: Icon(a.icon, size: 16.sp, color: a.tone),
              ),
              if (hasLine)
                Expanded(
                  child: Container(width: 1.5.w, constraints: BoxConstraints(minHeight: 12.h), color: AppColors.borderCardSoft),
                ),
            ],
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 6.h, 0, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(a.sub, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Notes" card: a composer plus a note list. Adding a note is local state
/// (prepended as "Manoj Varma · now").
class OpsNotesCard extends StatefulWidget {
  const OpsNotesCard({super.key, required this.initialNotes});
  final List<OpsNote> initialNotes;

  @override
  State<OpsNotesCard> createState() => _OpsNotesCardState();
}

class _OpsNotesCardState extends State<OpsNotesCard> {
  late final List<OpsNote> _notes = List.of(widget.initialNotes);
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _notes.insert(0, OpsNote(author: 'Manoj Varma', time: 'now', body: text));
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.note, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Notes', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42.h,
                  padding: EdgeInsets.symmetric(horizontal: 13.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.bgScreen,
                    borderRadius: BorderRadius.circular(11.r),
                    border: Border.all(color: const Color(0xFFE6E7EA)),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textBody),
                    cursorColor: AppColors.blueBright,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Add a note…',
                      hintStyle: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 9.w),
              GestureDetector(
                onTap: _add,
                child: Container(
                  width: 42.w,
                  height: 42.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                  child: Icon(PhosphorIconsFill.paperPlaneTilt, size: 16.sp, color: AppColors.white),
                ),
              ),
            ],
          ),
          for (final n in _notes)
            Padding(
              padding: EdgeInsets.only(top: 13.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28.w,
                    height: 28.w,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                    child: Text(opsInitials(n.author),
                        style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(n.author, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                            SizedBox(width: 7.w),
                            Text(n.time, style: AppText.micro(color: AppColors.textPlaceholder)),
                          ],
                        ),
                        SizedBox(height: 2.h),
                        Text(n.body, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textSecondary, height: 1.55)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
