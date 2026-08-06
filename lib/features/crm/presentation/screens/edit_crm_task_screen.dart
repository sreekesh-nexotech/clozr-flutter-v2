import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../components/lead_schema_form.dart';

/// Edit task — the org's own Task layout, rendered as a form.
///
/// Every field, its order and its label come from
/// `GET /crm/tasks/schema/?view_type=detail`, and the values from the task's
/// record. Because the same config trims the serializer, that layout is also
/// exactly the set the API will store — so there are no boxes here that accept
/// input the backend discards.
/// Also serves **Edit follow-up**: a follow-up is a Task with
/// `is_followup=true`, so the record, the write and this whole form are the
/// same. Only the schema differs — the two carry independent field configs —
/// along with the labels and which lists go stale on save.
class EditCrmTaskScreen extends ConsumerStatefulWidget {
  const EditCrmTaskScreen({super.key, this.isFollowup = false});

  /// Renders the org's Follow-up field set rather than its Task one.
  final bool isFollowup;

  @override
  ConsumerState<EditCrmTaskScreen> createState() => _EditCrmTaskScreenState();
}

class _EditCrmTaskScreenState extends ConsumerState<EditCrmTaskScreen> {
  final _formKey = GlobalKey<LeadSchemaFormState>();
  bool _saving = false;

  String get _noun => widget.isFollowup ? 'follow-up' : 'task';

  Future<void> _save(String id) async {
    if (_saving) return;
    final payload = _formKey.currentState?.payload ?? const <String, dynamic>{};
    if (payload.isEmpty) {
      ref.read(toastProvider.notifier).show('Nothing to save');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(crmTasksRepositoryProvider).updateTask(id, payload);
      if (!mounted) return;
      // The record and every list holding a copy are now stale. The activity
      // log refreshes itself off the write tick.
      ref.invalidate(taskRowProvider(id));
      if (widget.isFollowup) {
        ref.invalidate(followupsProvider);
        ref.invalidate(leadFollowupsProvider);
      } else {
        ref.invalidate(crmTasksProvider);
        ref.invalidate(leadTasksProvider);
      }
      ref.read(toastProvider.notifier).show(
          widget.isFollowup ? 'Follow-up updated' : 'Task updated');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ref.read(toastProvider.notifier).show(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    // Independent field configs — a follow-up's layout is not a task's.
    final schema = widget.isFollowup
        ? ref.watch(followupDetailSchemaProvider)
        : ref.watch(taskDetailSchemaProvider);
    // One record endpoint for both: a follow-up *is* a task.
    final row = ref.watch(taskRowProvider(id));

    // The pickers read these; watched here so they are loading by the time the
    // user opens one rather than starting on first tap.
    ref.watch(taskStatusOptionsProvider);
    ref.watch(taskPriorityOptionsProvider);
    ref.watch(teamOptionsProvider);

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: widget.isFollowup ? 'Follow-up' : 'Task',
            name: widget.isFollowup ? 'Edit follow-up' : 'Edit task',
            onBack: () => context.pop(),
          ),
          Expanded(
            child: switch (row) {
              AsyncValue(hasError: true) => Center(
                  child: Text('Could not load this task',
                      style: AppText.body(color: AppColors.textMuted)),
                ),
              AsyncValue(value: null, isLoading: true) => const DetailSkeleton(),
              _ => ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 24.h),
                  children: [
                    if (schema.editableColumns.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 32.h),
                        child: Text(
                          'This workspace has not configured any editable '
                          '$_noun fields yet.',
                          textAlign: TextAlign.center,
                          style: AppText.body(color: AppColors.textMuted),
                        ),
                      )
                    else
                      LeadSchemaForm(
                        key: _formKey,
                        schema: schema,
                        row: row.valueOrNull,
                      ),
                  ],
                ),
            },
          ),
          _actionBar(id),
        ],
      ),
    );
  }

  Widget _actionBar(String id) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 100.w,
              height: 48.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFE6E7EA)),
              ),
              child: Text('Cancel',
                  style: AppText.custom(
                      size: 14, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              onTap: _saving ? null : () => _save(id),
              child: Container(
                height: 48.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _saving ? AppColors.textPlaceholder : AppColors.navy,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: _saving
                    ? SizedBox(
                        width: 18.w,
                        height: 18.w,
                        child: const CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.white),
                          SizedBox(width: 8.w),
                          Text('Save changes',
                              style: AppText.custom(
                                  size: 15, weight: FontWeight.w700, color: AppColors.white)),
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
