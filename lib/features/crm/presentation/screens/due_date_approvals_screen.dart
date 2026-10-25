import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../components/crm_async.dart';
import '../components/due_date_change.dart';

/// Pending changes past the self-service limit that this user may decide —
/// the server scopes the rows (`GET /sla/due-date-changes/pending/`).
final pendingDueDateChangesProvider =
    FutureProvider.autoDispose.family<({int count, List<Map<String, dynamic>> rows}), int>((ref, pageSize) async {
  final body = await ref.read(apiServiceProvider).get('/sla/due-date-changes/pending/', query: {'page': 1, 'page_size': pageSize});
  final rows = body is Map && body['results'] is List
      ? [for (final r in body['results'] as List) if (r is Map) Map<String, dynamic>.from(r)]
      : <Map<String, dynamic>>[];
  return (count: body is Map ? (body['count'] as num?)?.toInt() ?? rows.length : rows.length, rows: rows);
});

/// The Tasks toolbar's "Due date approvals (N)"; 0 on any failure.
final pendingDueDateCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final body = await ref.read(apiServiceProvider).get('/sla/due-date-changes/pending/', query: {'page': 1, 'page_size': 1}, quiet: true);
    return body is Map ? (body['count'] as num?)?.toInt() ?? 0 : 0;
  } on Object {
    return 0;
  }
});

/// Webapp `DueDateApprovalsScreen`, as cards.
class DueDateApprovalsScreen extends ConsumerStatefulWidget {
  const DueDateApprovalsScreen({super.key});

  @override
  ConsumerState<DueDateApprovalsScreen> createState() => _DueDateApprovalsScreenState();
}

class _DueDateApprovalsScreenState extends ConsumerState<DueDateApprovalsScreen> {
  int _pageSize = 20;

  Future<void> _decide(Map<String, dynamic> change, bool approve) async {
    final ok = await decideDueDateChange(context, ref, change, approve: approve);
    if (!ok) return;
    ref.invalidate(pendingDueDateChangesProvider);
    ref.invalidate(pendingDueDateCountProvider);
    ref.invalidate(crmTasksProvider);
    ref.invalidate(taskRowProvider('${change['object_id']}'));
    ref.invalidate(followupRowProvider('${change['object_id']}'));
    ref.invalidate(followupsScopedProvider);
  }

  void _open(Map<String, dynamic> c) {
    final id = '${c['object_id'] ?? ''}';
    if (id.isEmpty) return;
    if (c['module'] == 'project_task') {
      context.push('${Routes.opsTaskDetail}?id=$id');
      return;
    }
    // `module=task` covers follow-ups too (they are Task rows); a follow-up
    // only opens on its own page.
    final followup = ref.read(followupsAllProvider).any((f) => f.id == id);
    context.push(followup ? '${Routes.followupDetail}?id=$id' : '${Routes.taskDetail}?id=$id');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(pendingDueDateChangesProvider(_pageSize));
    // Loaded so a tap knows whether a change belongs to a follow-up.
    ref.watch(followupsProvider);
    return Container(
      color: AppColors.bgDetail,
      child: Column(children: [
        DetailAppBar(section: 'Tasks', name: 'Due date approvals', onBack: () => context.pop()),
        Expanded(
          child: async.when(
            loading: () => const ListSkeleton(itemCount: 3),
            error: (e, _) => ErrorState.forError(crmAppError(e),
                onRetry: () => ref.invalidate(pendingDueDateChangesProvider)),
            data: (page) {
              if (page.rows.isEmpty) {
                return ListView(children: const [
                  EmptyState(
                    icon: PhosphorIconsRegular.sealCheck,
                    title: 'Nothing waiting for approval',
                    body: 'Due-date changes past the self-service limit show up here until someone up the reporting line decides. The record keeps its date until then.',
                  ),
                ]);
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(pendingDueDateChangesProvider),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 24.h),
                  children: [
                    for (final c in page.rows) _card(c),
                    if (page.count > page.rows.length)
                      TextButton(
                        onPressed: () => setState(() => _pageSize = _pageSize >= 50 ? 100 : 50),
                        child: Text('Showing ${page.rows.length} of ${page.count} — show more'),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final slip = c['slip_days'] as num?;
    final status = '${c['status'] ?? 'pending'}';
    final reason = '${c['reason_code'] ?? ''}'.trim();
    final note = '${c['reason_text'] ?? ''}'.trim();
    final pending = status == 'pending';
    final statusLabel = status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1);
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: ClozrCard(
        radius: 16,
        onTap: () => _open(c),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(c['module'] == 'project_task' ? 'Operations task' : 'Task', style: AppText.bodyStrong()),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
              decoration: BoxDecoration(
                color: pending ? AppColors.tintAmber : AppColors.bgChipGrey,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(statusLabel, style: AppText.captionStrong(color: pending ? AppColors.warningDeep : AppColors.textMuted)),
            ),
          ]),
          Text('${c['field'] ?? 'due date'}'.replaceAll('_', ' '), style: AppText.caption()),
          SizedBox(height: 8.h),
          Text.rich(TextSpan(style: AppText.body(), children: [
            TextSpan(text: '${dueDateLabel('${c['old_value'] ?? ''}')} → '),
            TextSpan(text: dueDateLabel('${c['new_value'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(
              text: '  ${slipLabel(slip)}',
              style: TextStyle(color: (slip ?? 0) > 0 ? AppColors.error : AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
          ])),
          SizedBox(height: 6.h),
          Text(reason.isEmpty ? '—' : reason, style: AppText.bodyStrong()),
          if (note.isNotEmpty) Text('“$note”', style: AppText.body(color: AppColors.textMuted)),
          SizedBox(height: 6.h),
          Text('${c['requested_by_name'] ?? ''} · ${dueDateLabel('${c['created_at'] ?? ''}')}', style: AppText.caption()),
          if (pending) ...[
            SizedBox(height: 10.h),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => _decide(c, false), child: const Text('Reject')),
              SizedBox(width: 10.w),
              FilledButton(onPressed: () => _decide(c, true), child: const Text('Approve')),
            ]),
          ],
        ]),
      ),
    );
  }
}
