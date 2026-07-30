import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../data/mock/mock_users.dart';
import '../../application/providers/ops_notes_providers.dart';
import '../../application/providers/ops_subtasks_providers.dart';
import '../../application/providers/ops_tasks_providers.dart';

/// Subtask detail (#12). Reached by tapping a subtask row inside Task Detail.
///
/// Shows the subtask title, a done toggle that writes back to the parent task's
/// subtask state (kept in sync with the detail list via [opsSubtasksProvider]),
/// the assignee, due date, a "Part of …" link back to the parent task, and a
/// subtask-local notes thread. Parent id + index arrive as query params.
class SubtaskDetailScreen extends ConsumerWidget {
  const SubtaskDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = GoRouterState.of(context).uri.queryParameters;
    final taskId = params['taskId'] ?? '';
    final index = int.tryParse(params['i'] ?? '') ?? -1;

    final task = ref.watch(opsTaskByIdProvider(taskId));
    final subtasks = ref.watch(opsSubtasksProvider(taskId));
    final valid = index >= 0 && index < subtasks.length;

    if (task == null || !valid) {
      return Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            _appBar(context, null),
            const Expanded(child: Center(child: Text('Subtask not found'))),
          ],
        ),
      );
    }

    final s = subtasks[index];
    final assignee = MockUsers.of(s.who);
    final notesKey = 'sub-$taskId#$index';

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _appBar(context, s.title),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
              children: [
                ClozrCard(
                  radius: 18,
                  padding: EdgeInsets.all(18.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title,
                          style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                      SizedBox(height: 4.h),
                      Text('Subtask of ${task.subject}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                      SizedBox(height: 16.h),
                      _doneToggle(context, ref, taskId, index, s.done),
                      const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 16)),
                      _metaRow(
                        icon: PhosphorIconsRegular.user,
                        label: 'Assignee',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 26.w,
                              height: 26.w,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                              child: Text(assignee.initials, style: AppText.custom(size: 9, weight: FontWeight.w700, color: AppColors.white)),
                            ),
                            SizedBox(width: 8.w),
                            Text(assignee.name, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                      SizedBox(height: 4.h),
                      _metaRow(
                        icon: PhosphorIconsRegular.calendarBlank,
                        label: 'Due date',
                        child: Text(s.due.isEmpty ? 'No due date' : s.due,
                            style: AppText.custom(
                                size: 14,
                                weight: FontWeight.w700,
                                color: s.due.isEmpty ? AppColors.textPlaceholder : AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                _partOfRow(context, task.subject),
                NotesThread(
                  notes: ref.watch(subtaskNotesProvider(notesKey)),
                  onAddNote: (body, atts) => ref.read(subtaskNotesProvider(notesKey).notifier).addNote(body, atts),
                  onAddReply: (noteId, body) => ref.read(subtaskNotesProvider(notesKey).notifier).addReply(noteId, body),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _appBar(BuildContext context, String? name) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: DetailAppBar(
        section: 'Subtask',
        name: name,
        onBack: () => context.pop(),
      ),
    );
  }

  Widget _doneToggle(BuildContext context, WidgetRef ref, String taskId, int index, bool done) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(opsSubtasksProvider(taskId).notifier).toggle(index),
      child: Container(
        height: 48.h,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: done ? AppColors.tintGreen : AppColors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: done ? AppColors.success : const Color(0xFFE6E7EA), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 22.w,
              height: 22.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? AppColors.success : AppColors.white,
                borderRadius: BorderRadius.circular(7.r),
                border: done ? null : Border.all(color: const Color(0xFFC9CCD2), width: 1.5),
              ),
              child: Icon(PhosphorIconsBold.check, size: 13.sp, color: done ? AppColors.white : Colors.transparent),
            ),
            SizedBox(width: 11.w),
            Text(done ? 'Completed' : 'Mark complete',
                style: AppText.custom(size: 14, weight: FontWeight.w700, color: done ? AppColors.success : AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _metaRow({required IconData icon, required String label, required Widget child}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Icon(icon, size: 16.sp, color: AppColors.textPlaceholder),
          SizedBox(width: 9.w),
          Text(label, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
          const Spacer(),
          Flexible(child: Align(alignment: Alignment.centerRight, child: child)),
        ],
      ),
    );
  }

  Widget _partOfRow(BuildContext context, String parentSubject) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.pop(),
      child: ClozrCard(
        radius: 18,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            Container(
              width: 34.w,
              height: 34.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.tintNavy, borderRadius: BorderRadius.circular(10.r)),
              child: Icon(PhosphorIconsRegular.listChecks, size: 17.sp, color: AppColors.navy),
            ),
            SizedBox(width: 11.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Part of', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  SizedBox(height: 1.h),
                  Text(parentSubject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Icon(PhosphorIconsRegular.caretRight, size: 15.sp, color: AppColors.textPlaceholder),
          ],
        ),
      ),
    );
  }
}
