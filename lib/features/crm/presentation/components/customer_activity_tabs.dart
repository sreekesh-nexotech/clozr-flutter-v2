import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/attachment_link.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/presentation/components/customer_accounting.dart';
import '../../../accounting/presentation/sheets/record_receipt_sheet.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/customer_activity_view.dart';
import '../../application/providers/attachments_providers.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/customer_activity_providers.dart';
import '../../application/providers/customer_activity_tabs_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/lead_file.dart';
import '../sheets/add_customer_call_log_sheet.dart';
import '../sheets/add_followup_sheet.dart';
import '../sheets/add_task_sheet.dart';
import 'call_log_actions.dart';
import 'crm_async.dart';
import 'crm_check_box.dart';
import 'crm_detail_parts.dart';

/// Invalidates every provider the activity tabs read — call from the detail
/// screen's pull-to-refresh.
void refreshCustomerActivityTabs(WidgetRef ref, String customerId) {
  ref.invalidate(customerTasksProvider(customerId));
  ref.invalidate(customerFollowupsProvider(customerId));
  ref.invalidate(customerCallItemsProvider(customerId));
  ref.invalidate(customerPaymentPlansProvider(customerId));
  ref.invalidate(customerLinkedLeadsProvider(customerId));
  ref.invalidate(customerFilesProvider(customerId));
  ref.invalidate(customerNoteTagsProvider(customerId));
}

/// The customer detail's "Customer activity" card — Tasks, Call log,
/// Follow-ups, Payments, Opportunities, Files (+ Accounting while active) —
/// ported from the webapp's `CustomerDetailScreen` tabs, in the mobile look.
///
/// Every Add follows its own module's create permission (task / call_log /
/// followup); Opportunities and Files follow `customer.update`. A tab whose
/// fetch is refused shows the shared "No access" notice with Retry.
class CustomerActivityTabs extends ConsumerStatefulWidget {
  const CustomerActivityTabs({
    super.key,
    required this.customer,
    this.onUpsell,
    this.onRecordPayment,
  });

  final Customer customer;

  /// Opportunities tab's "New lead" — the screen's upsell flow. Null hides it.
  final Future<void> Function()? onUpsell;

  /// Payments tab's "Record payment". Null keeps the explanatory toast.
  final Future<void> Function()? onRecordPayment;

  @override
  ConsumerState<CustomerActivityTabs> createState() => _CustomerActivityTabsState();
}

class _CustomerActivityTabsState extends ConsumerState<CustomerActivityTabs> {
  int _tab = 0;
  bool _uploading = false;

  static const _baseTabs = ['Tasks', 'Call log', 'Follow-ups', 'Payments', 'Opportunities', 'Files'];

  Customer get _cust => widget.customer;

  /// Accounting is not a tab: as on web it is the detail screen's own panel
  /// (`CustomerAccountingPanel`), shown only while accounting is active.
  List<String> get _tabLabels => _baseTabs;

  /// Lead id → reference ("LD-0021"), for "From lead …" tags.
  Map<String, String> get _leadRefs => {
        for (final l in ref.watch(customerLinkedLeadsProvider(_cust.id)).valueOrNull ?? const <CustomerLinkedLead>[])
          l.id: l.reference.isNotEmpty ? l.reference : l.name,
      };

  // ───────────────────────────── CTA ─────────────────────────────

  Future<void> _cta() async {
    final toast = ref.read(toastProvider.notifier);
    final need = switch (_tab) {
      0 => ('task', PermVerb.create),
      1 => ('call_log', PermVerb.create),
      2 => ('followup', PermVerb.create),
      3 => widget.onRecordPayment != null ? ('payment', PermVerb.create) : null,
      4 || 5 => ('customer', PermVerb.update),
      _ => null,
    };
    if (need != null && !ensurePermission(ref, need.$1, need.$2)) return;
    final link = (id: _cust.id, label: _cust.name);
    switch (_tab) {
      case 0:
        await showAddTaskSheet(context, ref, customer: link);
        if (mounted) ref.invalidate(customerTasksProvider(_cust.id));
      case 1:
        final saved = await showAddCustomerCallLogSheet(context,
            customerId: _cust.id, customerName: _cust.name, customerPhone: _cust.phone);
        if (saved && mounted) ref.invalidate(customerCallItemsProvider(_cust.id));
      case 2:
        await showAddFollowupSheet(context, ref, customer: link);
        if (mounted) {
          ref.invalidate(customerFollowupsProvider(_cust.id));
          refreshFollowups(ref);
        }
      case 3:
        final record = widget.onRecordPayment;
        if (record == null) {
          toast.show('Payments are recorded against an invoice.');
        } else {
          await record();
          if (mounted) ref.invalidate(customerPaymentPlansProvider(_cust.id));
        }
      case 4:
        await widget.onUpsell?.call();
        if (mounted) ref.invalidate(customerLinkedLeadsProvider(_cust.id));
      case 5:
        await _uploadFiles();
      default:
        if (ref.read(accPermProvider('acc_settlement')).create) {
          await showRecordReceiptSheet(context, customerId: _cust.id);
        } else {
          await context.push('${Routes.accNewInvoice}?customer=${_cust.id}');
        }
    }
  }

  Future<void> _uploadFiles() async {
    if (_uploading) return;
    final toast = ref.read(toastProvider.notifier);
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    } on Object catch (e) {
      if (mounted) toast.showError('Could not open the file picker: $e');
      return;
    }
    if (picked == null || !mounted) return;
    final files = [
      for (final f in picked.files)
        if (f.path != null) (path: f.path!, name: f.name),
    ];
    if (files.isEmpty) return;
    if (!ApiConfig.apiEnabled) {
      toast.show('Files upload once the app is connected to the API.');
      return;
    }
    setState(() => _uploading = true);
    final repo = ref.read(attachmentsRepositoryProvider);
    var stored = 0;
    String? failure;
    for (final f in files) {
      try {
        final saved = await repo.uploadFile(relatedTo: 'customer', relatedToId: _cust.id, path: f.path, name: f.name);
        if (saved != null) stored++;
      } on AppError catch (e) {
        ref.read(apiServiceProvider).handled(e);
        failure = e.message;
        break;
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    if (stored > 0) ref.invalidate(customerFilesProvider(_cust.id));
    if (failure != null) {
      toast.showError(stored == 0 ? failure : '$stored uploaded · $failure');
    } else {
      toast.show(stored == 1 ? 'File uploaded' : '$stored files uploaded');
    }
  }

  // ───────────────────────────── card ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final labels = _tabLabels;
    if (_tab >= labels.length) _tab = 0;
    final ctaLabels = [
      'Add task',
      'Add call log',
      'Add follow-up',
      'Record payment',
      'New lead',
      _uploading ? 'Uploading…' : 'Upload file',
      ref.watch(accPermProvider('acc_settlement')).create ? 'Record receipt' : 'New invoice',
    ];
    final showCta = !(_tab == 4 && widget.onUpsell == null);
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Customer activity',
                      style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary))),
              if (showCta)
                GestureDetector(
                  onTap: _cta,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9.r), border: Border.all(color: const Color(0xFFE6E7EA))),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_tab == 5 ? PhosphorIconsRegular.uploadSimple : PhosphorIconsBold.plus,
                            size: 13.sp, color: AppColors.textSecondary),
                        SizedBox(width: 6.w),
                        Text(ctaLabels[_tab], style: AppText.bodyStrong()),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 14.h),
          DetailUnderlineTabs(labels: labels, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          SizedBox(height: 6.h),
          switch (_tab) {
            0 => _tasksTab(),
            1 => _callLogTab(),
            2 => _followupsTab(),
            3 => _paymentsTab(),
            4 => _opportunitiesTab(),
            5 => _filesTab(),
            _ => CustomerAccountingTab(customerId: _cust.id),
          },
        ],
      ),
    );
  }

  /// Loading / error ("No access" + Retry on a 403) / empty / data.
  Widget _tabAsync<T>(
    AsyncValue<List<T>> async, {
    required Widget empty,
    required Widget Function(List<T> items) data,
    required VoidCallback onRetry,
  }) {
    return async.when(
      loading: () => ListSkeleton(itemCount: 3, itemHeight: 54.h, padding: EdgeInsets.symmetric(vertical: 14.h)),
      error: (e, _) => ErrorState.forError(crmAppError(e), onRetry: onRetry),
      data: (items) => items.isEmpty ? empty : data(items),
    );
  }

  Widget _miniPill(StatusMeta meta, {bool strike = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
      decoration: BoxDecoration(color: meta.color.withOpacity(0.09), borderRadius: BorderRadius.circular(7.r)),
      child: Text(meta.label,
          style: AppText.custom(size: 11, weight: FontWeight.w700, color: meta.color)
              .copyWith(decoration: strike ? TextDecoration.lineThrough : null)),
    );
  }

  /// The "From lead LD-…" chip on a converted lead's history row.
  Widget _historyChip(String text) => Container(
        margin: EdgeInsets.only(top: 5.h),
        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
        decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.08), borderRadius: BorderRadius.circular(6.r)),
        child: Text(text, style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.navy)),
      );

  String? _historyOf(Map<String, dynamic> raw) {
    final p = relatedParentOf(raw);
    return leadHistoryTag(
        parentModel: p.model, parentId: p.id, customerId: _cust.id, reference: p.reference, leadRefs: _leadRefs);
  }

  // ───────────────────────────── Tasks ─────────────────────────────

  String _taskStatus(CrmTask t) => ref.watch(crmTaskStatusOverrideProvider)[t.id] ?? t.status;

  StatusMeta _taskMeta(CrmTask t) {
    final statuses = ref.watch(taskStatusCatalogProvider).valueOrNull ?? const [];
    final key = _taskStatus(t);
    if (key == t.status) return crmTaskStatusMeta(t, statuses);
    for (final s in statuses) {
      if (crmTaskStatusKey(name: s.name, type: s.statusType) == key) return StatusMeta(s.name, crmTaskStatusColor(s));
    }
    return StatusMeta$.task[key] ?? StatusMeta$.task['todo']!;
  }

  static final _dueFormat = DateFormat('dd MMM yyyy');

  DateTime? _dueOf(String due) {
    final s = due.trim();
    if (s.isEmpty) return null;
    try {
      return _dueFormat.parseStrict(s);
    } on FormatException {
      return DateTime.tryParse(s);
    }
  }

  static const _badgeColors = {
    'Done': AppColors.success,
    'Overdue': AppColors.error,
    'Today': AppColors.error,
    'Upcoming': AppColors.blueBright,
  };

  /// Ticks a task done or reopens it; a refusal (e.g. "A task must have at
  /// least one note before it can be completed.") rolls back and is toasted.
  Future<void> _toggleTask(CrmTask t) async {
    final next = _taskStatus(t) == 'done' ? 'todo' : 'done';
    final prev = ref.read(crmTaskStatusOverrideProvider);
    ref.read(crmTaskStatusOverrideProvider.notifier).state = {...prev, t.id: next};
    if (ApiConfig.apiEnabled) {
      try {
        await ref.read(crmTasksRepositoryProvider).setTaskStatusByKey(t.id, next);
      } on AppError catch (e) {
        ref.read(apiServiceProvider).handled(e);
        final rolled = {...ref.read(crmTaskStatusOverrideProvider)};
        if (prev.containsKey(t.id)) {
          rolled[t.id] = prev[t.id]!;
        } else {
          rolled.remove(t.id);
        }
        ref.read(crmTaskStatusOverrideProvider.notifier).state = rolled;
        if (mounted) ref.read(toastProvider.notifier).showError(e.bareMessage.isEmpty ? e.message : e.bareMessage);
        return;
      }
      if (!mounted) return;
      ref.invalidate(customerTasksProvider(_cust.id));
      ref.invalidate(crmTasksProvider);
      ref.invalidate(taskRowProvider(t.id));
    }
    if (mounted) ref.read(toastProvider.notifier).show(next == 'done' ? 'Task completed' : 'Task reopened');
  }

  Widget _tasksTab() {
    return _tabAsync<CrmTask>(
      ref.watch(customerTasksProvider(_cust.id)),
      onRetry: () => ref.invalidate(customerTasksProvider(_cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.checkSquare,
          title: 'No tasks yet.',
          body: 'Tasks linked to this customer will appear here.'),
      data: (tasks) => Column(children: [for (final t in tasks) _taskRow(t)]),
    );
  }

  Widget _taskRow(CrmTask t) {
    final done = _taskStatus(t) == 'done';
    final due = _dueOf(t.due);
    final when = done ? 'Completed' : (due == null ? 'No due date' : 'Due ${_dueFormat.format(due)}');
    final who = MockUsers.of(t.assignee).name;
    final sub = who.isEmpty || who == 'Unknown' ? when : '$when · ${who.split(' ').first}';
    final badge = taskDueBadge(due: due, done: done);
    final fromLead = _historyOf(t.raw);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 13.h, horizontal: 2.w),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CrmCheckBox(done: done, onTap: () => _toggleTask(t)),
          SizedBox(width: 12.w),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('${Routes.taskDetail}?id=${t.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.titleClean,
                      style: AppText.custom(
                              size: 14,
                              weight: FontWeight.w600,
                              color: done ? AppColors.textPlaceholder : AppColors.textPrimary)
                          .copyWith(decoration: done ? TextDecoration.lineThrough : null)),
                  SizedBox(height: 3.h),
                  Text(sub, style: AppText.caption()),
                  if (fromLead != null) _historyChip(fromLead),
                ],
              ),
            ),
          ),
          SizedBox(width: 8.w),
          _miniPill(badge == null ? _taskMeta(t) : StatusMeta(badge, _badgeColors[badge]!)),
        ],
      ),
    );
  }

  // ───────────────────────────── Call log ─────────────────────────────

  Widget _callLogTab() {
    return _tabAsync<CustomerCallItem>(
      ref.watch(customerCallItemsProvider(_cust.id)),
      onRetry: () => ref.invalidate(customerCallItemsProvider(_cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.phone,
          title: 'No calls logged yet.',
          body: 'Calls made to or received from this customer will appear here.'),
      data: (calls) => Column(children: [for (final c in calls) _callRow(c)]),
    );
  }

  Widget _callRow(CustomerCallItem item) {
    final c = item.log;
    final row = item.row;
    final fromLead = leadHistoryTag(
        parentModel: row.parentModel, parentId: row.parentId, customerId: _cust.id, leadRefs: _leadRefs);
    final icon = c.isMissed
        ? PhosphorIconsRegular.phoneX
        : row.isOutgoing
            ? PhosphorIconsRegular.phoneOutgoing
            : PhosphorIconsRegular.phoneIncoming;
    final tone = c.isMissed
        ? AppColors.error
        : !c.connected
            ? AppColors.textPlaceholder
            : row.isOutgoing
                ? AppColors.success
                : AppColors.blueBright;
    final exotel = row.medium == 'Exotel';
    final meta = row.metaLine();
    final content = Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 2.w),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38.w,
            height: 38.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
            child: Icon(icon, size: 18.sp, color: tone),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7.w,
                  runSpacing: 4.h,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(row.direction.isEmpty ? 'Call' : row.direction, style: AppText.bodyStrong()),
                    if (row.medium.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                        decoration: BoxDecoration(
                            color: exotel ? AppColors.navy.withOpacity(0.08) : AppColors.bgChipGrey,
                            borderRadius: BorderRadius.circular(99.r)),
                        child: Text(row.medium,
                            style: AppText.custom(
                                size: 10.5,
                                weight: FontWeight.w700,
                                color: exotel ? AppColors.navy : AppColors.textMuted)),
                      ),
                    if (c.hasRecording) Icon(PhosphorIconsFill.playCircle, size: 16.sp, color: AppColors.blueBright),
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  SizedBox(height: 3.h),
                  Text(meta, style: AppText.caption()),
                ],
                if (fromLead != null) _historyChip(fromLead),
                if (c.summary.isNotEmpty) ...[
                  SizedBox(height: 5.h),
                  Text(c.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)
                          .copyWith(height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final allowActivity = fromLead == null;
    final hasActions = allowActivity || c.hasRecording || (c.transcript.isNotEmpty && c.summary.isEmpty);
    if (!hasActions) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await showCallLogActions(context, ref, call: c, leadId: _cust.id, allowActivity: allowActivity,
            onPlay: () async {
          final failure = await openAttachment(c.recordingUrl);
          if (failure != null && mounted) ref.read(toastProvider.notifier).showError(failure);
        });
        if (mounted) ref.invalidate(customerCallItemsProvider(_cust.id));
      },
      child: content,
    );
  }

  // ───────────────────────────── Follow-ups ─────────────────────────────

  Future<void> _toggleFollowup(Followup f) async {
    final done = f.status != 'done';
    try {
      await ref.read(followupsRepositoryProvider).setFollowupDone(f.id, done);
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) ref.read(toastProvider.notifier).showError(e.bareMessage.isEmpty ? e.message : e.bareMessage);
      return;
    }
    if (!mounted) return;
    ref.invalidate(customerFollowupsProvider(_cust.id));
    refreshFollowups(ref);
    ref.read(toastProvider.notifier).show(done ? 'Task completed' : 'Task reopened');
  }

  Widget _followupsTab() {
    return _tabAsync<Followup>(
      ref.watch(customerFollowupsProvider(_cust.id)),
      onRetry: () => ref.invalidate(customerFollowupsProvider(_cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.clock,
          title: 'No follow-ups yet.',
          body: 'Follow-ups scheduled for this customer will appear here.'),
      data: (fus) => Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: Column(children: [for (final f in fus) _followupRow(f)]),
      ),
    );
  }

  Widget _followupRow(Followup f) {
    final fromLead = _historyOf(f.raw);
    final hasDue = f.due.trim().isNotEmpty && !f.due.contains('No due');
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.r), border: Border.all(color: AppColors.borderCardSoft)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('${Routes.followupDetail}?id=${f.id}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 10.h, right: 10.w),
              child: CrmCheckBox(done: f.status == 'done', onTap: () => _toggleFollowup(f)),
            ),
            Container(
              width: 42.w,
              height: 42.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(12.r)),
              child: Icon(PhosphorIconsRegular.calendarBlank, size: 19.sp, color: AppColors.navy),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.title.isEmpty ? '${f.kind} follow-up' : f.title,
                      style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 3.h),
                  Text('${f.kind.trim().isEmpty ? 'Follow-up' : f.kind}${hasDue ? ' · ${f.due}' : ''}',
                      style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)),
                  if (f.description.trim().isNotEmpty) ...[
                    SizedBox(height: 3.h),
                    Text(f.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(color: AppColors.textPlaceholder)),
                  ],
                  if (fromLead != null) _historyChip(fromLead),
                ],
              ),
            ),
            _miniPill(StatusMeta$.followup[f.status] ?? StatusMeta$.followup['due']!),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────── Payments ─────────────────────────────

  Widget _paymentsTab() {
    return _tabAsync<CustomerPayment>(
      ref.watch(customerPaymentPlansProvider(_cust.id)),
      onRetry: () => ref.invalidate(customerPaymentPlansProvider(_cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.receipt,
          title: 'No payments yet.',
          body: 'Payment plans from accepted quotes will appear here.'),
      data: (plans) => Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: Column(children: [for (final p in plans) _planCard(p)]),
      ),
    );
  }

  Widget _planCard(CustomerPayment p) {
    final pill = paymentPlanPill(p);
    final note = paymentPlanNote(p);
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.all(14.r),
            decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(14.r)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(PhosphorIconsRegular.receipt, size: 16.sp, color: AppColors.navy),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(paymentPlanTitle(p),
                          style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    SizedBox(width: 8.w),
                    _miniPill(StatusMeta(
                        pill.label,
                        pill.done
                            ? AppColors.success
                            : pill.label == 'Cancelled'
                                ? AppColors.textMuted
                                : AppColors.blueBright)),
                  ],
                ),
                SizedBox(height: 12.h),
                Wrap(
                  spacing: 20.w,
                  runSpacing: 10.h,
                  children: [
                    for (final s in paymentPlanStats(p))
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.label, style: AppText.caption()),
                          SizedBox(height: 2.h),
                          Text(activityMoney(s.value),
                              style: AppText.custom(
                                  size: 15,
                                  weight: FontWeight.w800,
                                  color: switch (s.tone) {
                                    StatTone.success => AppColors.success,
                                    StatTone.muted => AppColors.textMuted,
                                    StatTone.normal => AppColors.textPrimary,
                                  })),
                        ],
                      ),
                  ],
                ),
                if (note.isNotEmpty) ...[
                  SizedBox(height: 8.h),
                  Text(note, style: AppText.caption()),
                ],
              ],
            ),
          ),
          for (final row in paymentPlanRows(p)) _installmentRow(p, row),
        ],
      ),
    );
  }

  Widget _installmentRow(CustomerPayment p, PaymentRowView row) {
    final meta = paymentRowMeta(p, row);
    final color = switch (row.statusLabel) {
      'Paid' => AppColors.success,
      'Partly paid' => AppColors.warning,
      'Overdue' => AppColors.error,
      'Cancelled' => AppColors.textMuted,
      _ => AppColors.blueBright,
    };
    return Opacity(
      opacity: row.cancelled ? 0.6 : 1,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 2.w),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34.w,
              height: 34.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: row.done ? AppColors.success.withOpacity(0.1) : AppColors.bgChipGrey,
                  borderRadius: BorderRadius.circular(10.r)),
              child: Icon(PhosphorIconsRegular.fileText,
                  size: 16.sp, color: row.done ? AppColors.success : AppColors.textSecondary),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.title,
                      style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
                  if (meta.isNotEmpty) ...[
                    SizedBox(height: 3.h),
                    Text(meta, style: AppText.caption()),
                  ],
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _miniPill(StatusMeta(row.statusLabel, color)),
                SizedBox(height: 5.h),
                Text(activityMoney(row.amount),
                    style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)
                        .copyWith(decoration: row.cancelled ? TextDecoration.lineThrough : null)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────── Opportunities ─────────────────────────────

  Widget _opportunitiesTab() {
    return _tabAsync<CustomerLinkedLead>(
      ref.watch(customerLinkedLeadsProvider(_cust.id)),
      onRetry: () => ref.invalidate(customerLinkedLeadsProvider(_cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.trendUp,
          title: 'No opportunities yet.',
          body: 'Use Upsell (or create a quote) to start one.'),
      data: (leads) => Column(children: [for (final l in leads) _opportunityRow(l)]),
    );
  }

  Color _hex(String hex, Color fallback) {
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null || h.length < 6 ? fallback : Color(v);
  }

  Widget _opportunityRow(CustomerLinkedLead l) {
    final meta = l.metaLine;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.leadDetail}?id=${l.id}'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 13.h, horizontal: 2.w),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: l.isConverted ? AppColors.success.withOpacity(0.1) : AppColors.bgChipGrey,
                  borderRadius: BorderRadius.circular(11.r)),
              child: Icon(l.isSource ? PhosphorIconsRegular.user : PhosphorIconsRegular.trendUp,
                  size: 17.sp, color: l.isConverted ? AppColors.success : AppColors.navy),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 5.h),
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 4.h,
                    children: [
                      _miniPill(l.isSource
                          ? const StatusMeta('ORIGINAL DEAL', AppColors.navy)
                          : const StatusMeta('UPSELL', AppColors.warning)),
                      if (l.statusName.isNotEmpty)
                        _miniPill(StatusMeta(l.statusName.toUpperCase(), _hex(l.statusColor, AppColors.textMuted))),
                      if (l.isConverted) _miniPill(const StatusMeta('CONVERTED', AppColors.success)),
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    SizedBox(height: 5.h),
                    Text(meta, style: AppText.caption()),
                  ],
                ],
              ),
            ),
            if (l.value != null) ...[
              SizedBox(width: 8.w),
              Text(activityMoney(l.value),
                  style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ],
        ),
      ),
    );
  }

  // ───────────────────────────── Files ─────────────────────────────

  Widget _filesTab() {
    return _tabAsync<LeadFile>(
      ref.watch(customerFilesProvider(_cust.id)),
      onRetry: () => ref.invalidate(customerFilesProvider(_cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.paperclip,
          title: 'No files shared',
          body: 'Drawings, BOQs and documents will appear here.'),
      data: (files) => Column(
        children: [
          for (final f in files)
            InkWell(
              onTap: () async {
                final failure = await openAttachment(f.url);
                if (failure != null && mounted) ref.read(toastProvider.notifier).showError(failure);
              },
              borderRadius: BorderRadius.circular(10.r),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 2.w),
                child: Row(
                  children: [
                    Container(
                      width: 38.w,
                      height: 38.w,
                      alignment: Alignment.center,
                      decoration:
                          BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
                      child: Icon(PhosphorIconsRegular.paperclip, size: 18.sp, color: AppColors.textSecondary),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                          SizedBox(height: 3.h),
                          Text([f.ext, if (f.uploadedAt.isNotEmpty) f.uploadedAt].join(' · '),
                              style: AppText.caption()),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Icon(PhosphorIconsRegular.arrowSquareOut, size: 16.sp, color: AppColors.textPlaceholder),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
