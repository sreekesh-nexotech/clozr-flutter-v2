import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';

/// The prototype's `#EEF1F4` icon-chip tint (same square used on the lead card).
/// No exact design token exists for it, so it lives here as the single source.
const Color kIconChipBg = Color(0xFFEEF1F4);

/// A rounded square holding a navy glyph — the leading icon on every finance
/// card / detail header (40×40 on list rows, 46×46 in detail headers).
class IconChip extends StatelessWidget {
  const IconChip({super.key, required this.icon, this.size = 40, this.radius = 11, this.iconSize = 19, this.bg = kIconChipBg, this.color = AppColors.navy});
  final IconData icon;
  final double size;
  final double radius;
  final double iconSize;
  final Color bg;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.w,
      height: size.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius.r)),
      child: Icon(icon, size: iconSize.sp, color: color),
    );
  }
}

/// White rounded-18 detail card with an optional bold section title. The finance
/// detail screens are built almost entirely from stacks of these.
class FinanceCard extends StatelessWidget {
  const FinanceCard({super.key, this.title, required this.child, this.padding});
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClozrCard(
      radius: 18,
      padding: padding ?? EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            SizedBox(height: 6.h),
          ],
          child,
        ],
      ),
    );
  }
}

/// A label ⋯ value row with a hairline underline — the repeated meta row inside
/// "Quote details" / "Payment details" / "Pricing" / "Details" cards.
class MetaRow extends StatelessWidget {
  const MetaRow({super.key, required this.label, required this.value, this.last = false});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5))),
            ),
      child: Row(
        children: [
          Text(label, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
          SizedBox(width: 14.w),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// One entry in an [ActivityTimeline].
class ActivityEntry {
  final IconData icon;
  final Color tone;
  final Color bg;
  final String title;
  final String sub;
  const ActivityEntry({required this.icon, required this.tone, required this.bg, required this.title, required this.sub});
}

/// The vertical activity timeline: icon chip + connecting line, title + sub.
class ActivityTimeline extends StatelessWidget {
  const ActivityTimeline({super.key, required this.entries});
  final List<ActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < entries.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 34.w,
                      height: 34.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: entries[i].bg, shape: BoxShape.circle),
                      child: Icon(entries[i].icon, size: 16.sp, color: entries[i].tone),
                    ),
                    if (i < entries.length - 1)
                      Expanded(
                        child: Container(width: 1.5, color: AppColors.borderCardSoft, constraints: BoxConstraints(minHeight: 12.h)),
                      ),
                  ],
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 6.h, bottom: 16.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entries[i].title, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text(entries[i].sub, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A seeded note (used by the product detail notes list).
class NoteEntry {
  final String initials;
  final String author;
  final String time;
  final String body;
  const NoteEntry({required this.initials, required this.author, required this.time, required this.body});
}

/// The "Notes" / "Internal notes" card: header, an add-note input (send fires
/// [onSend] with the draft), and any seeded notes below.
class NotesCard extends StatefulWidget {
  const NotesCard({
    super.key,
    this.title = 'Notes',
    this.icon = PhosphorIconsRegular.note,
    this.notes = const [],
    required this.onSend,
    this.countLabel,
  });

  final String title;
  final IconData icon;
  final List<NoteEntry> notes;
  final ValueChanged<String> onSend;
  final String? countLabel;

  @override
  State<NotesCard> createState() => _NotesCardState();
}

class _NotesCardState extends State<NotesCard> {
  final _ctrl = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    widget.onSend(v);
    _ctrl.clear();
    setState(() => _hasText = false);
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
              Icon(widget.icon, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text(widget.title, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
              if (widget.countLabel != null) ...[
                SizedBox(width: 8.w),
                Text(widget.countLabel!, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ],
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44.h,
                  padding: EdgeInsets.symmetric(horizontal: 13.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.bgScreen,
                    borderRadius: BorderRadius.circular(11.r),
                    border: Border.all(color: const Color(0xFFE6E7EA)),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    onChanged: (v) => setState(() => _hasText = v.trim().isNotEmpty),
                    onSubmitted: (_) => _send(),
                    style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textBody),
                    cursorColor: AppColors.blueBright,
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
                onTap: _send,
                child: Container(
                  width: 44.w,
                  height: 44.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _hasText ? AppColors.navy : const Color(0xFFC7CBD3),
                    borderRadius: BorderRadius.circular(11.r),
                  ),
                  child: Icon(PhosphorIconsFill.paperPlaneTilt, size: 16.sp, color: AppColors.white),
                ),
              ),
            ],
          ),
          for (final n in widget.notes) ...[
            SizedBox(height: 13.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28.w,
                  height: 28.w,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                  child: Text(n.initials, style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(n.author, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          SizedBox(width: 7.w),
                          Text(n.time, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                        ],
                      ),
                      SizedBox(height: 2.h),
                      Text(n.body,
                          style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textSecondary, height: 1.55)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
