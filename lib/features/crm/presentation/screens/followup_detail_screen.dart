import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/models/note.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/followup.dart';
import '../components/crm_detail_parts.dart';
import 'crm_status_sheet.dart';

/// Follow-up kind → Phosphor glyph (mirrors the prototype's FUKIND map).
const _fuKindIcons = <String, IconData>{
  'Call': PhosphorIconsRegular.phone,
  'Meeting': PhosphorIconsRegular.usersThree,
  'Site visit': PhosphorIconsRegular.mapPin,
  'Email': PhosphorIconsRegular.envelopeSimple,
  'Callback': PhosphorIconsRegular.phoneIncoming,
  'Payment': PhosphorIconsRegular.currencyInr,
};

class FollowupDetailScreen extends ConsumerStatefulWidget {
  const FollowupDetailScreen({super.key});

  @override
  ConsumerState<FollowupDetailScreen> createState() => _FollowupDetailScreenState();
}

class _FollowupDetailScreenState extends ConsumerState<FollowupDetailScreen> {
  final _notesKey = GlobalKey<NotesThreadState>();

  /// Scrolls the notes card into view and focuses the composer (#13).
  void _focusNotes() {
    final ctx = _notesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.05, curve: Curves.easeOut);
    }
    _notesKey.currentState?.focusComposer();
  }

  /// Records a status change for an existing follow-up so the detail + list
  /// reflect it immediately (see `followupStatusOverrideProvider`).
  void _setStatus(WidgetRef ref, String id, String status) {
    final overrides = ref.read(followupStatusOverrideProvider);
    ref.read(followupStatusOverrideProvider.notifier).state = {...overrides, id: status};
  }

  void _openFollowupMenu(Followup fu) {
    final toast = ref.read(toastProvider.notifier);
    showActionMenu(
      context,
      actions: [
        MenuAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit follow-up', onTap: () => toast.show('Edit follow-up')),
        MenuAction(icon: PhosphorIconsRegular.calendarPlus, label: 'Reschedule', onTap: () => toast.show('Reschedule follow-up')),
        MenuAction(icon: PhosphorIconsRegular.notePencil, label: 'Add note', onTap: _focusNotes),
        MenuAction(icon: PhosphorIconsRegular.trash, label: 'Delete follow-up', destructive: true, onTap: () => toast.show('Follow-up deleted')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final fu = ref.watch(followupByIdProvider(id));

    if (fu == null) {
      return Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Follow-up', onBack: () => context.pop()),
            const Expanded(child: Center(child: Text('Follow-up not found'))),
          ],
        ),
      );
    }

    final meta = StatusMeta$.followup[fu.status] ?? StatusMeta$.followup['due']!;
    final owner = MockUsers.of(fu.owner);
    final done = fu.status == 'done';
    final title = fu.agenda.isNotEmpty ? fu.agenda : '${fu.kind} — ${fu.company}';

    // Resolve the related record for the "Related" card.
    final customers = ref.watch(customersProvider).valueOrNull ?? const [];
    final leads = ref.watch(leadsProvider).valueOrNull ?? const [];
    String relatedName = fu.company;
    String relatedSub = '—';
    String? relatedRoute;
    String? relatedId;
    if (fu.custId != null) {
      final c = customers.where((c) => c.id == fu.custId).toList();
      if (c.isNotEmpty) {
        relatedName = c.first.company ?? c.first.name;
        relatedSub = 'Customer · #${c.first.id}';
        relatedRoute = Routes.customerDetail;
        relatedId = c.first.id;
      }
    } else if (fu.leadId != null) {
      final l = leads.where((l) => l.id == fu.leadId).toList();
      if (l.isNotEmpty) {
        relatedName = l.first.company ?? l.first.name;
        relatedSub = 'Lead · #${l.first.id}';
        relatedRoute = Routes.leadDetail;
        relatedId = l.first.id;
      }
    }

    // Notes thread (#13) — follow-ups start with an empty thread; the shared
    // composer stays usable regardless of the follow-up's status.
    final notesSeed = CrmNotesSeed('FU-${fu.id}', () => <NoteEntry>[]);
    final notes = ref.watch(crmNotesProvider(notesSeed));

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Follow-up',
            name: title,
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => _openFollowupMenu(fu),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headCard(context, ref, fu, meta),
                SizedBox(height: 14.h),
                _relatedCard(context, relatedName, relatedSub, relatedRoute, relatedId),
                SizedBox(height: 14.h),
                _detailsCard(fu, meta, owner),
                SizedBox(height: 14.h),
                _filesCard(ref),
                SizedBox(height: 14.h),
                NotesThread(
                  key: _notesKey,
                  notes: notes,
                  onAddNote: (body, atts) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addNote(body, atts, const NoteAuthor()),
                  onAddReply: (noteId, body) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addReply(noteId, body, const NoteAuthor()),
                ),
                SizedBox(height: 14.h),
                _activityCard(meta, owner),
              ],
            ),
          ),
          _bottomBar(ref, fu, done),
        ],
      ),
    );
  }

  Widget _headCard(BuildContext context, WidgetRef ref, Followup fu, StatusMeta meta) {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(11.r)),
                child: Icon(_fuKindIcons[fu.kind] ?? PhosphorIconsRegular.phone, size: 19.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fu.company, style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                    SizedBox(height: 3.h),
                    Text('${fu.kind} follow-up · ${fu.contact}', style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 5.h),
                    Text('Due ${fu.due} · ${fu.time}',
                        style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: fu.status == 'overdue' ? AppColors.error : AppColors.textLabelAlt)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 13.h),
          GestureDetector(
            onTap: () => showCrmStatusSheet(
              context: context,
              ref: ref,
              title: 'Update follow-up status',
              options: const ['overdue', 'due', 'done'],
              meta: StatusMeta$.followup,
              current: fu.status,
              onSelect: (k) {
                _setStatus(ref, fu.id, k);
                ref.read(toastProvider.notifier).show('Status set to ${StatusMeta$.followup[k]!.label}');
              },
            ),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(color: meta.color.withOpacity(0.09), borderRadius: BorderRadius.circular(9.r)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
                  SizedBox(width: 7.w),
                  Text(meta.label, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: meta.color)),
                  SizedBox(width: 6.w),
                  Icon(PhosphorIconsBold.caretDown, size: 10.sp, color: AppColors.textMuted2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _relatedCard(BuildContext context, String name, String sub, String? route, String? id) {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
      onTap: route == null ? null : () => context.push('$route?id=$id'),
      child: Row(
        children: [
          Container(
            width: 42.w,
            height: 42.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(12.r)),
            child: Icon(PhosphorIconsRegular.buildings, size: 20.sp, color: AppColors.navy),
          ),
          SizedBox(width: 13.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RELATED', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
                SizedBox(height: 2.h),
                Text(name, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 1.h),
                Text(sub, style: AppText.caption()),
              ],
            ),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 15.sp, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }

  Widget _detailsCard(Followup fu, StatusMeta meta, dynamic owner) {
    final rows = <(String, String)>[
      ('Type', fu.kind),
      ('Status', meta.label),
      ('Due', '${fu.due} · ${fu.time}'),
      ('Contact', fu.contact),
      ('Follow-up ID', '#${fu.id}'),
      ('Owner', owner.name),
    ];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          for (int i = 0; i < rows.length; i++)
            DetailInfoRow(label: rows[i].$1, value: rows[i].$2, last: i == rows.length - 1),
          SizedBox(height: 14.h),
          Text('AGENDA', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
          SizedBox(height: 6.h),
          Text(fu.agenda.isEmpty ? '—' : fu.agenda,
              style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textSecondary).copyWith(height: 1.55)),
        ],
      ),
    );
  }

  Widget _filesCard(WidgetRef ref) {
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.paperclip, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Files', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.read(toastProvider.notifier).show('Opening file picker…'),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(9.r), border: Border.all(color: const Color(0xFFE6E7EA))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.uploadSimple, size: 13.sp, color: AppColors.textSecondary),
                      SizedBox(width: 6.w),
                      Text('Upload', style: AppText.bodyStrong()),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text('No files attached yet.', style: AppText.caption(color: AppColors.textPlaceholder)),
        ],
      ),
    );
  }

  Widget _activityCard(StatusMeta meta, dynamic owner) {
    final items = <ActivityItem>[
      ActivityItem(icon: PhosphorIconsRegular.arrowsClockwise, tone: AppColors.blueBright, bg: AppColors.tintBlue, title: 'Status set to ${meta.label}', sub: '${owner.name} · 2 hours ago'),
      const ActivityItem(icon: PhosphorIconsRegular.calendarPlus, tone: AppColors.success, bg: AppColors.tintGreen, title: 'Follow-up scheduled', sub: 'Manoj Varma · 3 days ago'),
    ];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.pulse, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Activity', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          ActivityTimeline(items: items),
        ],
      ),
    );
  }

  Widget _bottomBar(WidgetRef ref, Followup fu, bool done) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _focusNotes,
            child: Container(
              width: 48.w,
              height: 48.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.borderInput)),
              child: Icon(PhosphorIconsRegular.notePencil, size: 21.sp, color: AppColors.navy),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              onTap: () {
                _setStatus(ref, fu.id, done ? 'due' : 'done');
                ref.read(toastProvider.notifier).show(done ? 'Follow-up reopened' : 'Follow-up marked done');
              },
              child: Container(
                height: 48.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? AppColors.tintGreen : AppColors.navy,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(done ? PhosphorIconsFill.checkCircle : PhosphorIconsBold.check, size: 17.sp, color: done ? AppColors.success : AppColors.white),
                    SizedBox(width: 8.w),
                    Text(done ? 'Done · reopen' : 'Mark done',
                        style: AppText.custom(size: 15, weight: FontWeight.w700, color: done ? AppColors.success : AppColors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
