import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/crm_task.dart';
import '../components/crm_detail_parts.dart';
import 'crm_status_sheet.dart';

/// Task type → Phosphor glyph (mirrors the prototype's TASKTYPES map).
const _taskTypeIcons = <String, IconData>{
  'Task': PhosphorIconsRegular.checkSquare,
  'Call': PhosphorIconsRegular.phone,
  'Email': PhosphorIconsRegular.envelopeSimple,
  'Meeting': PhosphorIconsRegular.usersThree,
  'Deadline': PhosphorIconsRegular.flag,
  'Site visit': PhosphorIconsRegular.mapPin,
  'Quote': PhosphorIconsRegular.fileText,
  'Admin': PhosphorIconsRegular.clipboardText,
  'Follow-up': PhosphorIconsRegular.arrowUUpRight,
};

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  int _tab = 0; // 0 = Description, 1 = Files

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final task = ref.watch(crmTaskByIdProvider(id));

    if (task == null) {
      return Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Task', onBack: () => context.pop()),
            const Expanded(child: Center(child: Text('Task not found'))),
          ],
        ),
      );
    }

    final meta = StatusMeta$.task[task.status] ?? StatusMeta$.task['todo']!;
    final assignee = MockUsers.of(task.assignee);
    final leads = ref.watch(leadsProvider).valueOrNull ?? const [];
    final lead = task.leadId == null ? null : leads.where((l) => l.id == task.leadId).firstOrNull;
    final done = task.status == 'done';

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Task',
            name: task.title,
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => ref.read(toastProvider.notifier).show('Task actions'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _titleCard(task, meta),
                if (lead != null) ...[SizedBox(height: 14.h), _relatedCard(lead)],
                SizedBox(height: 14.h),
                _infoCard(task, assignee),
                SizedBox(height: 14.h),
                _descFilesCard(task, lead),
                SizedBox(height: 14.h),
                _notesCard(),
                SizedBox(height: 14.h),
                _activityCard(task, meta, assignee),
              ],
            ),
          ),
          _bottomBar(task, done),
        ],
      ),
    );
  }

  Widget _titleCard(CrmTask task, StatusMeta meta) {
    final overdue = task.isOverdue;
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
                width: 46.w,
                height: 46.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(13.r)),
                child: Icon(_taskTypeIcons[task.type] ?? PhosphorIconsRegular.checkSquare, size: 22.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title, style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3, height: 1.3)),
                    SizedBox(height: 3.h),
                    Text('${task.id} · ${task.type} task', style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 5.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('Due ${task.due}', style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                        if (task.dueNote.isNotEmpty) ...[
                          SizedBox(width: 8.w),
                          Text(task.dueNote,
                              style: AppText.custom(size: 12, weight: FontWeight.w700, color: overdue ? AppColors.error : AppColors.warningDeep)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            children: [
              _statusChip(meta, () => _openStatusSheet(task, meta)),
              SizedBox(width: 9.w),
              PriorityPill(priority: task.priority),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(StatusMeta meta, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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
    );
  }

  void _openStatusSheet(CrmTask task, StatusMeta meta) {
    showCrmStatusSheet(
      context: context,
      ref: ref,
      title: 'Update task status',
      options: const ['todo', 'inprogress', 'blocked', 'done'],
      meta: StatusMeta$.task,
      current: task.status,
    );
  }

  Widget _relatedCard(dynamic lead) {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
      onTap: () => context.push('${Routes.leadDetail}?id=${lead.id}'),
      child: Row(
        children: [
          Container(
            width: 42.w,
            height: 42.w,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFFEEF1F4), shape: BoxShape.circle),
            child: Text(lead.initials, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.navy)),
          ),
          SizedBox(width: 13.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RELATED TO', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
                SizedBox(height: 2.h),
                Text(lead.company ?? lead.name, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 1.h),
                Text('Lead · #${lead.id}', style: AppText.caption()),
              ],
            ),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 15.sp, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }

  Widget _infoCard(CrmTask task, dynamic assignee) {
    final rows = <(IconData, String, String)>[
      (PhosphorIconsRegular.tag, 'Type', task.type),
      (PhosphorIconsRegular.flag, 'Priority', task.priority),
      (PhosphorIconsRegular.calendarBlank, 'Due date', task.due),
      (PhosphorIconsRegular.userCircle, 'Assigned to', assignee.name),
      (PhosphorIconsRegular.hash, 'Task ID', task.id),
      (PhosphorIconsRegular.clockCounterClockwise, 'Created', '3 days ago'),
    ];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Task information', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          for (int i = 0; i < rows.length; i++)
            Container(
              padding: EdgeInsets.symmetric(vertical: 9.h),
              decoration: BoxDecoration(
                border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F5))),
              ),
              child: Row(
                children: [
                  SizedBox(width: 20.w, child: Icon(rows[i].$1, size: 17.sp, color: AppColors.textPlaceholder)),
                  SizedBox(width: 12.w),
                  SizedBox(width: 92.w, child: Text(rows[i].$2, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted))),
                  Expanded(
                    child: Text(rows[i].$3, textAlign: TextAlign.right, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _descFilesCard(CrmTask task, dynamic lead) {
    final desc = lead != null
        ? 'A ${task.priority.toLowerCase()}-priority ${task.type.toLowerCase()} task linked to lead ${lead.company} (#${lead.id}). Due ${task.due}.'
        : 'A ${task.priority.toLowerCase()}-priority ${task.type.toLowerCase()} task. Due ${task.due}.';
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailUnderlineTabs(labels: const ['Description', 'Files'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
          if (_tab == 0)
            Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: Text(desc, style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textLabelAlt).copyWith(height: 1.6)),
            )
          else
            DetailTabEmpty(
              icon: PhosphorIconsRegular.paperclip,
              title: 'No files attached',
              body: 'Files attached to this task will appear here.',
              cta: GestureDetector(
                onTap: () => ref.read(toastProvider.notifier).show('Opening file picker…'),
                child: Container(
                  height: 40.h,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10.r), border: Border.all(color: AppColors.borderInput)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.uploadSimple, size: 15.sp, color: AppColors.navy),
                      SizedBox(width: 7.w),
                      Text('Upload file', style: AppText.bodyStrong()),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42.h,
                  padding: EdgeInsets.symmetric(horizontal: 13.w),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: AppColors.bgScreen,
                    borderRadius: BorderRadius.circular(11.r),
                    border: Border.all(color: const Color(0xFFE6E7EA)),
                  ),
                  child: Text('Add a note…', style: AppText.body(color: AppColors.textPlaceholder)),
                ),
              ),
              SizedBox(width: 9.w),
              GestureDetector(
                onTap: () => ref.read(toastProvider.notifier).show('Note added'),
                child: Container(
                  width: 42.w,
                  height: 42.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                  child: Icon(PhosphorIconsFill.paperPlaneTilt, size: 16.sp, color: AppColors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activityCard(CrmTask task, StatusMeta meta, dynamic assignee) {
    final items = <ActivityItem>[
      ActivityItem(icon: PhosphorIconsRegular.arrowsClockwise, tone: AppColors.blueBright, bg: AppColors.tintBlue, title: 'Status set to ${meta.label}', sub: '${assignee.name} · 2 hours ago'),
      ActivityItem(icon: PhosphorIconsRegular.userPlus, tone: AppColors.success, bg: AppColors.tintGreen, title: 'Assigned to ${assignee.name}', sub: 'Manoj Varma · 3 days ago'),
      const ActivityItem(icon: PhosphorIconsRegular.plusCircle, tone: AppColors.textMuted2, bg: AppColors.bgChipGrey, title: 'Task created', sub: 'Manoj Varma · 3 days ago'),
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

  Widget _bottomBar(CrmTask task, bool done) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ref.read(toastProvider.notifier).show('Add a note'),
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
              onTap: () => ref.read(toastProvider.notifier).show(done ? 'Task reopened' : 'Task marked complete'),
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
                    Text(done ? 'Completed · reopen' : 'Mark complete',
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

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
