import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/tickets_providers.dart';
import '../../domain/entities/ticket.dart';
import '../../infrastructure/data_sources/local/tickets_mock_ds.dart';
import '../util/ticket_sla.dart';

class _LocalNote {
  final String body;
  final bool internal;
  const _LocalNote(this.body, this.internal);
}

/// Ticket detail — summary + status/assignee, SLA banner (paused when Pending),
/// details, linked tasks, an Internal-note / Reply composer and the audit log.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key});

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  String? _status; // local status override
  List<String>? _assignees; // local assignee override
  int _noteMode = 0; // 0 = internal, 1 = reply
  final _noteCtrl = TextEditingController();
  final List<_LocalNote> _notes = [];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uri = GoRouterState.of(context).uri;
    final id = uri.queryParameters['id'] ?? '';
    final fromBoard = uri.queryParameters['from'] == 'board';
    final base = ref.watch(ticketByIdProvider(id));

    if (base == null) {
      return Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            _header(subject: 'Not found', fromBoard: fromBoard),
            const Expanded(child: Center(child: Text('Ticket not found'))),
          ],
        ),
      );
    }

    final t = base.copyWith(status: _status, assignees: _assignees);
    final meta = StatusMeta$.ticket[t.status] ?? StatusMeta$.ticket['new']!;

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _header(subject: t.subject, fromBoard: fromBoard),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
              children: [
                _summaryCard(t, meta),
                _slaBanner(t),
                if (t.isLocked) _lockCard(),
                SizedBox(height: 14.h),
                _detailsCard(t),
                SizedBox(height: 14.h),
                _linkedTasksCard(t),
                SizedBox(height: 14.h),
                _notesCard(),
                SizedBox(height: 14.h),
                _auditCard(t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──
  Widget _header({required String subject, required bool fromBoard}) {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 12.h),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.canPop() ? context.pop() : context.go(Routes.helpHome),
            child: Padding(
              padding: EdgeInsets.only(right: fromBoard ? 4.w : 12.w),
              child: Icon(PhosphorIconsBold.caretLeft, size: 22.sp, color: AppColors.textPrimary),
            ),
          ),
          if (fromBoard)
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Text('Back to Support Overview',
                  style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Ticket ',
                style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3),
                children: [
                  TextSpan(
                    text: '/ $subject',
                    style: AppText.custom(size: 16, weight: FontWeight.w600, color: AppColors.textPlaceholder),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(toastProvider.notifier).show('Ticket actions'),
            child: SizedBox(
              width: 34.w,
              height: 34.w,
              child: Icon(PhosphorIconsBold.dotsThreeVertical, size: 21.sp, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary ──
  Widget _summaryCard(Ticket t, StatusMeta meta) {
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.subject,
                        style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3, height: 1.3)),
                    SizedBox(height: 5.h),
                    Row(
                      children: [
                        Text(t.id, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                        if (t.status == 'resolved') ...[
                          SizedBox(width: 8.w),
                          Flexible(
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                              decoration: BoxDecoration(color: AppColors.tintPurple, borderRadius: BorderRadius.circular(7.r)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(PhosphorIconsRegular.hourglassMedium, size: 11.sp, color: AppColors.pending),
                                  SizedBox(width: 4.w),
                                  Flexible(
                                    child: Text('Auto-closes after confirmation period',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.pending)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => _openStatusSheet(t),
                    child: StatusPill.meta(meta),
                  ),
                  SizedBox(height: 5.h),
                  StatusPill(label: t.pri, color: ticketPriPillColor(t.pri)),
                ],
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => t.isLocked ? ref.read(toastProvider.notifier).show('This ticket is closed — reopen to edit') : _openAssigneeSheet(t),
            child: Row(
              children: [
                _avatarStack(t.assignees, 28),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text('Assignees',
                      style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                ),
                if (!t.isLocked)
                  Row(
                    children: [
                      Icon(PhosphorIconsRegular.pencilSimple, size: 13.sp, color: AppColors.blueBright),
                      SizedBox(width: 4.w),
                      Text('Edit', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.blueBright)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarStack(List<String> ids, double size) {
    final shown = ids.take(2).toList();
    final more = ids.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shown.isNotEmpty)
          AvatarStack(
            items: [
              for (final id in shown)
                (MockUsers.of(id).initials, MockUsers.of(id).color),
            ],
            size: size,
            overlap: 7,
            fontSize: size * 0.36,
          ),
        if (more > 0) ...[
          SizedBox(width: 5.w),
          Text('+$more', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textMuted2)),
        ],
      ],
    );
  }

  // ── SLA banner ──
  Widget _slaBanner(Ticket t) {
    final now = kNowList.millisecondsSinceEpoch;
    final paused = t.isPaused;
    final respMs = t.respByISO != null ? DateTime.parse(t.respByISO!).millisecondsSinceEpoch - now : null;
    final resMs = t.resolveByISO != null ? DateTime.parse(t.resolveByISO!).millisecondsSinceEpoch - now : null;
    final resBreached = t.resolved == null && resMs != null && resMs < 0;

    final respLabel = t.responded != null
        ? 'met ${t.responded!.contains(', ') ? t.responded!.split(', ')[1] : t.responded}'
        : (paused ? 'paused' : (respMs != null && respMs < 0 ? 'breached' : 'due ${t.respByLabel ?? ''}'));
    final respTone = t.responded != null
        ? AppColors.success
        : (respMs != null && respMs < 0 && !paused ? AppColors.error : AppColors.textMuted2);
    final respIcon = t.responded != null
        ? PhosphorIconsFill.checkCircle
        : (paused ? PhosphorIconsFill.pause : PhosphorIconsRegular.clock);

    final resLabel = t.resolved != null
        ? 'met ${t.resolved}'
        : (paused
            ? 'frozen — waiting on customer'
            : '${t.resolveByLabel ?? '—'}${resMs != null ? (resMs < 0 ? ' — breached ${fmtLeft(resMs)} ago' : ' — ${fmtLeft(resMs)} left') : ''}');
    final resTone = t.resolved != null
        ? AppColors.success
        : (resBreached && !paused ? AppColors.error : AppColors.textMuted2);
    final resIcon = t.resolved != null
        ? PhosphorIconsFill.checkCircle
        : (paused ? PhosphorIconsFill.pause : (resBreached ? PhosphorIconsFill.warningCircle : PhosphorIconsRegular.clock));

    final bg = paused ? AppColors.bgChipGrey : (resBreached ? AppColors.tintRed : AppColors.bgScreen);

    return Container(
      margin: EdgeInsets.only(top: 14.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14.r)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (paused) ...[
            Row(
              children: [
                Icon(PhosphorIconsFill.pauseCircle, size: 17.sp, color: AppColors.textMuted2),
                SizedBox(width: 8.w),
                Text('SLA paused — waiting on customer',
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
              ],
            ),
            SizedBox(height: 8.h),
          ],
          _slaLine('First response', respLabel, respIcon, respTone),
          SizedBox(height: 8.h),
          _slaLine('Resolution due', resLabel, resIcon, resTone),
        ],
      ),
    );
  }

  Widget _slaLine(String title, String value, IconData icon, Color tone) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15.sp, color: tone),
        SizedBox(width: 9.w),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: title,
              style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textPrimary),
              children: [
                TextSpan(
                  text: ' · $value',
                  style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: tone),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lockCard() {
    return Container(
      margin: EdgeInsets.only(top: 14.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(14.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.lockSimple, size: 18.sp, color: AppColors.textMuted2),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This ticket is closed — fields are locked. Reopen to edit.',
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
                SizedBox(height: 2.h),
                Text('Status and notes stay editable.',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Details ──
  Widget _detailsCard(Ticket t) {
    final cust = TicketDirectory.customer(t.custId);
    final proj = TicketDirectory.project(t.projId);
    final rows = <(String, String)>[
      ('Requester', cust?.display ?? '—'),
      ('Contact person', t.contact),
      ('Channel', t.channel),
      ('Category', t.cat),
      ('Product / service', t.product ?? '—'),
      ('Related project', proj?.name ?? t.projId ?? '—'),
      ('Created', t.created),
      ('First responded', t.responded ?? 'Awaiting'),
      ('Resolved', t.resolved ?? '—'),
    ];
    final vColor = t.isLocked ? AppColors.textPlaceholder : AppColors.textPrimary;
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 4.h),
          for (final r in rows)
            Container(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$1, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Text(r.$2,
                        textAlign: TextAlign.right,
                        style: AppText.custom(size: 14, weight: FontWeight.w700, color: vColor)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: 10.h),
            child: Text(t.desc,
                style: AppText.body(color: t.isLocked ? AppColors.textPlaceholder : AppColors.textLabelAlt).copyWith(height: 1.6)),
          ),
          if (!t.isLocked) ...[
            SizedBox(height: 14.h),
            GestureDetector(
              onTap: () => context.push('${Routes.editTicket}?id=${t.id}'),
              child: Container(
                height: 44.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppColors.borderCard, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.pencilSimple, size: 15.sp, color: AppColors.textSecondary),
                    SizedBox(width: 7.w),
                    Text('Edit ticket', style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Linked tasks ──
  Widget _linkedTasksCard(Ticket t) {
    final taskIds = [if (t.taskId != null) t.taskId!];
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.linkSimple, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Linked tasks', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          if (taskIds.isNotEmpty) ...[
            SizedBox(height: 12.h),
            for (final tid in taskIds)
              Container(
                margin: EdgeInsets.only(bottom: 8.h),
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppColors.borderCardSoft),
                ),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.listChecks, size: 17.sp, color: AppColors.navy),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(tid,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
                    ),
                    if (t.projId != null) ...[
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(color: AppColors.tintNavy, borderRadius: BorderRadius.circular(7.r)),
                        child: Text(t.projId!, style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.navy)),
                      ),
                      SizedBox(width: 8.w),
                    ],
                    Icon(PhosphorIconsBold.caretRight, size: 12.sp, color: AppColors.textPlaceholder),
                  ],
                ),
              ),
          ],
          if (!t.isLocked)
            GestureDetector(
              onTap: () => ref.read(toastProvider.notifier).show('Create task from ticket'),
              child: Container(
                margin: EdgeInsets.only(top: 12.h),
                height: 44.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11.r),
                  border: Border.all(color: AppColors.borderInput),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.plus, size: 15.sp, color: AppColors.navy),
                    SizedBox(width: 8.w),
                    Text('Create task from ticket', style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
                  ],
                ),
              ),
            )
          else
            Container(
              margin: EdgeInsets.only(top: 12.h),
              height: 44.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsFill.lockSimple, size: 14.sp, color: AppColors.textPlaceholder),
                  SizedBox(width: 8.w),
                  Text('Locked — reopen the ticket to create tasks',
                      style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Notes ──
  Widget _notesCard() {
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
          Container(
            padding: EdgeInsets.all(4.r),
            decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
            child: Row(
              children: [
                _noteSeg('Internal note', PhosphorIconsRegular.lockSimple, 0),
                SizedBox(width: 6.w),
                _noteSeg('Reply', PhosphorIconsRegular.chatTeardropText, 1),
              ],
            ),
          ),
          SizedBox(height: 10.h),
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
                    border: Border.all(color: AppColors.borderCard),
                  ),
                  child: TextField(
                    controller: _noteCtrl,
                    style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textBody),
                    cursorColor: AppColors.blueBright,
                    onSubmitted: (_) => _addNote(),
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
                onTap: _addNote,
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
          for (final n in _notes) _noteRow(n),
        ],
      ),
    );
  }

  Widget _noteSeg(String label, IconData icon, int mode) {
    final active = _noteMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _noteMode = mode),
        child: Container(
          height: 32.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8.r),
            boxShadow: active
                ? [BoxShadow(color: const Color(0xFF101828).withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13.sp, color: active ? AppColors.navy : AppColors.textMuted),
              SizedBox(width: 6.w),
              Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: active ? AppColors.navy : AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteRow(_LocalNote n) {
    return Padding(
      padding: EdgeInsets.only(top: 13.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28.w,
            height: 28.w,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
            child: Text('MV', style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('You', style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(width: 7.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: n.internal ? AppColors.bgChipGrey : AppColors.blueSubtle,
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(n.internal ? 'Internal' : 'Reply',
                          style: AppText.custom(size: 10, weight: FontWeight.w700, color: n.internal ? AppColors.textMuted2 : AppColors.blueBright)),
                    ),
                    SizedBox(width: 7.w),
                    Text('Just now', style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                ),
                SizedBox(height: 3.h),
                Text(n.body, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textLabelAlt).copyWith(height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNote() {
    final body = _noteCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _notes.insert(0, _LocalNote(body, _noteMode == 0));
      _noteCtrl.clear();
    });
    ref.read(toastProvider.notifier).show(_noteMode == 0 ? 'Internal note added' : 'Reply added');
  }

  // ── Audit log ──
  Widget _auditCard(Ticket t) {
    final entries = _buildAudit(t);
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
                        Expanded(child: Container(width: 1.5.w, color: AppColors.borderCardSoft, constraints: BoxConstraints(minHeight: 12.h))),
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
      ),
    );
  }

  List<_Audit> _buildAudit(Ticket t) {
    final now = kNowList.millisecondsSinceEpoch;
    final resMs = t.resolveByISO != null ? DateTime.parse(t.resolveByISO!).millisecondsSinceEpoch - now : null;
    final resBreached = t.resolved == null && resMs != null && resMs < 0;
    final firstName = t.assignees.isNotEmpty ? MockUsers.of(t.assignees.first).name : '—';
    final out = <_Audit>[];
    if (t.status == 'closed') {
      out.add(_Audit(PhosphorIconsRegular.lockSimple, AppColors.textMuted2, AppColors.bgChipGrey, 'Ticket closed', 'Manoj Varma · ${t.resolved ?? '—'}'));
    }
    if (t.status == 'resolved' || t.status == 'closed') {
      out.add(_Audit(PhosphorIconsRegular.checkCircle, AppColors.success, AppColors.tintGreen, 'Marked resolved', '$firstName · ${t.resolved ?? '—'}'));
    }
    if (resBreached) {
      out.add(_Audit(PhosphorIconsRegular.warningCircle, AppColors.error, AppColors.tintRed, 'SLA resolution breached', 'System · due ${t.resolveByLabel ?? '—'}'));
    }
    if (t.status == 'pending') {
      out.add(_Audit(PhosphorIconsRegular.pauseCircle, AppColors.warning, AppColors.tintAmber, 'Status changed — Open → Pending', '$firstName · waiting on customer'));
    }
    if (t.responded != null) {
      out.add(_Audit(PhosphorIconsRegular.check, AppColors.success, AppColors.tintGreen, 'SLA response target met', 'First reply ${t.responded}'));
    }
    out.add(_Audit(PhosphorIconsRegular.userPlus, AppColors.pending, AppColors.tintPurple, 'Assignee changed', '$firstName assigned · Manoj Varma'));
    out.add(_Audit(PhosphorIconsRegular.arrowsClockwise, AppColors.blueBright, AppColors.tintBlue, 'Status changed — New → Open', 'Manoj Varma · ${t.created}'));
    out.add(_Audit(PhosphorIconsRegular.plusCircle, AppColors.navy, AppColors.tintNavy, 'Ticket created', '${t.channel} · ${t.created}'));
    return out;
  }

  // ── Status sheet ──
  void _openStatusSheet(Ticket t) {
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: 'Update status'),
            for (final key in const ['new', 'open', 'pending', 'resolved', 'closed'])
              _statusOption(ctx, t, key),
          ],
        ),
      ),
    );
  }

  Widget _statusOption(BuildContext ctx, Ticket t, String key) {
    final meta = StatusMeta$.ticket[key]!;
    final active = t.status == key;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _status = key);
        Navigator.of(ctx).pop();
        ref.read(toastProvider.notifier).show('Status → ${meta.label}');
      },
      child: Container(
        margin: EdgeInsets.fromLTRB(18.w, 0, 18.w, 8.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
        decoration: BoxDecoration(
          color: active ? AppColors.blueSubtle : AppColors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: active ? const Color(0xFFA6D1FF) : AppColors.borderCardSoft, width: active ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(width: 10.w, height: 10.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
            SizedBox(width: 11.w),
            Expanded(child: Text(meta.label, style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary))),
            if (active) Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.blueBright),
          ],
        ),
      ),
    );
  }

  // ── Assignee sheet ──
  void _openAssigneeSheet(Ticket t) {
    final selected = List<String>.from(t.assignees);
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(title: 'Assignees'),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(horizontal: 18.w),
                  children: [
                    for (final r in MockUsers.reps)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setSheet(() {
                            if (selected.contains(r.id)) {
                              selected.remove(r.id);
                            } else {
                              selected.add(r.id);
                            }
                          });
                          setState(() => _assignees = List<String>.from(selected));
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.h),
                          child: Row(
                            children: [
                              Container(
                                width: 36.w,
                                height: 36.w,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
                                child: Text(r.initials, style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.white)),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.name, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                                    SizedBox(height: 1.h),
                                    Text(r.role, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                                  ],
                                ),
                              ),
                              _checkbox(selected.contains(r.id)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkbox(bool on) {
    return Container(
      width: 22.w,
      height: 22.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? AppColors.navy : AppColors.white,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: on ? AppColors.navy : AppColors.borderInput, width: 1.5),
      ),
      child: on ? Icon(PhosphorIconsBold.check, size: 13.sp, color: AppColors.white) : null,
    );
  }
}

class _Audit {
  final IconData icon;
  final Color tone;
  final Color bg;
  final String title;
  final String sub;
  const _Audit(this.icon, this.tone, this.bg, this.title, this.sub);
}
