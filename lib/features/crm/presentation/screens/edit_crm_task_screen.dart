import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/paginated.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../components/due_date_change.dart';
import '../components/lead_schema_form.dart';
import '../sheets/add_sheet_kit.dart';

/// The org's default task status and priority, and the statuses a new task
/// may start in (webapp `creatableStatuses` / `defaultStatusId`).
final taskFormDefaultsProvider =
    FutureProvider.autoDispose<({String? status, String? priority, Set<String> creatable})>((ref) async {
  final api = ref.read(apiServiceProvider);
  String? status;
  String? priority;
  final creatable = <String>{};
  try {
    final body = await api.get(ApiEndpoints.crmTaskStatuses, query: {'page_size': 100}, quiet: true);
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results
        .where((s) => s['is_active'] != false)
        .toList()
      ..sort((a, b) => ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0));
    bool closed(Map s) =>
        s['is_completed'] == true || s['is_cancelled'] == true || s['status_type'] == 'completed' || s['status_type'] == 'cancelled';
    for (final s in rows) {
      if (!closed(s)) creatable.add('${s['crm_task_status_id']}');
    }
    final def = rows.where((s) => s['is_default'] == true && const {'open', 'in_progress', null}.contains(s['status_type'])).firstOrNull ??
        rows.where((s) => s['status_type'] == 'open').firstOrNull ??
        rows.where((s) => s['status_type'] == null).firstOrNull;
    status = def == null ? null : '${def['crm_task_status_id']}';
  } on Object {
    // No defaults — the server picks.
  }
  try {
    final body = await api.get(ApiEndpoints.taskPriorities, query: {'page_size': 100}, quiet: true);
    final p = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m)
        .results
        .where((p) => p['is_default'] == true && p['is_active'] != false)
        .firstOrNull;
    priority = p == null ? null : '${p['task_priority_id']}';
  } on Object {
    // No default priority.
  }
  return (status: status, priority: priority, creatable: creatable);
});

/// Webapp `dueDateProblem` — bounds 01-Jan-2000 … today + 5 years.
String? taskDueDateProblem(String iso) {
  if (iso.isEmpty) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return 'Enter a valid date.';
  if (d.isBefore(DateTime(2000, 1, 1))) return "The due date can't be before 01-Jan-2000.";
  final now = DateTime.now();
  final max = DateTime(now.year + 5, now.month, now.day);
  if (d.isAfter(max)) return "The due date can't be more than 5 years ahead (latest ${dmyLabel(max)}).";
  return null;
}

/// `08-Dec-2025`.
String dmyLabel(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day.toString().padLeft(2, '0')}-${m[d.month - 1]}-${d.year}';
}

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

  // ── create-only extras (webapp AddTaskModal) ──
  /// Related to: `lead` | `customer`, and the picked record.
  String _relatedKind = 'lead';
  ({String id, String label})? _related;

  bool _meetingOpen = false;
  DateTime? _meetingFrom;
  DateTime? _meetingTo;
  final _location = TextEditingController();
  String? _meetingError;
  String? _formError;

  String get _noun => widget.isFollowup ? 'follow-up' : 'task';

  /// The record behind the form. A follow-up is only found with
  /// `?is_followup=true`; the plain task URL is a 404 for it.
  FutureProvider<Map<String, dynamic>?> _rowProvider(String id) =>
      widget.isFollowup ? followupRowProvider(id) : taskRowProvider(id);

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  static String? _dueDateProblem(String iso) => taskDueDateProblem(iso);

  static String _dmy(DateTime d) => dmyLabel(d);

  String get _dueIso => _formKey.currentState?.valueOf('due_date').trim() ?? '';

  bool get _overdue {
    final d = DateTime.tryParse(_dueIso);
    if (d == null) return false;
    final now = DateTime.now();
    return d.isBefore(DateTime(now.year, now.month, now.day));
  }

  void _onFormChanged() {
    final type = _formKey.currentState?.valueOf('task_type') ?? '';
    setState(() {
      if (RegExp('meet', caseSensitive: false).hasMatch(type)) _meetingOpen = true;
    });
  }

  Future<void> _save(String id) async {
    if (_saving) return;
    final form = _formKey.currentState;
    final creating = id.isEmpty;
    final errors = form?.validate() ?? const <String>[];
    final dueProblem = _dueDateProblem(_dueIso);
    if (dueProblem != null) {
      form?.showErrors({'due_date': dueProblem});
      ref.read(toastProvider.notifier).showError(dueProblem);
      return;
    }
    if (errors.isNotEmpty) {
      ref.read(toastProvider.notifier).showError(errors.first);
      return;
    }
    if (_meetingFrom != null && _meetingTo != null && _meetingTo!.isBefore(_meetingFrom!)) {
      setState(() => _meetingError = 'Meeting end cannot be before the meeting start.');
      return;
    }
    final payload = {...?form?.payload};
    if (creating) {
      if (_related != null) {
        payload['related_to'] = _relatedKind;
        payload['related_to_id'] = _related!.id;
      }
      if (_meetingFrom != null) payload['meeting_from'] = _meetingFrom!.toUtc().toIso8601String();
      if (_meetingTo != null) payload['meeting_to'] = _meetingTo!.toUtc().toIso8601String();
      if (_location.text.trim().isNotEmpty) payload['location'] = _location.text.trim();
    }
    if (payload.isEmpty) {
      ref.read(toastProvider.notifier).show('Nothing to save');
      return;
    }
    // Webapp: a past due date asks before creating an overdue task.
    if (creating && _overdue) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Create an overdue task?'),
          content: Text('The due date ${_dmy(DateTime.parse(_dueIso))} has already passed, so this task will be overdue as soon as it is created.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Change date')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create task')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });
    var pending = false;
    try {
      if (creating) {
        await ref.read(crmTasksRepositoryProvider).createTask({...payload, 'is_followup': widget.isFollowup});
      } else {
        // Moving the due date goes through the reason / approval flow.
        final hadDate = '${ref.read(_rowProvider(id)).valueOrNull?['due_date'] ?? ''}'.isNotEmpty;
        final path = widget.isFollowup ? '${ApiEndpoints.crmTask(id)}?is_followup=true' : ApiEndpoints.crmTask(id);
        final r = await writeWithDueDateFlow(context, ref, path: path, fields: payload, hadDate: hadDate);
        if (r == DueDateWrite.cancelled) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        pending = r == DueDateWrite.pending;
      }
      if (!mounted) return;
      if (id.isNotEmpty) ref.invalidate(_rowProvider(id));
      if (widget.isFollowup) {
        refreshFollowups(ref);
        ref.invalidate(leadFollowupsProvider);
      } else {
        ref.invalidate(crmTasksProvider);
        ref.invalidate(leadTasksProvider);
      }
      if (!pending) {
        ref.read(toastProvider.notifier).show(switch ((creating, widget.isFollowup)) {
          (true, true) => 'Follow-up created',
          (true, false) => 'Task created',
          (false, true) => 'Follow-up updated',
          (false, false) => 'Task updated',
        });
      }
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      // Webapp: field errors under their inputs, the message as an alert at
      // the bottom of the form and a toast — without the `field:` prefix.
      final firsts = {
        for (final f in (e.fieldErrors ?? const <String, List<String>>{}).entries)
          if (f.value.isNotEmpty) f.key: f.value.first,
      };
      if (firsts.isNotEmpty) form?.showErrors(firsts);
      ref.read(apiServiceProvider).handled(e);
      final msg = firsts.isNotEmpty
          ? firsts.values.first
          : (e.message.isEmpty ? (creating ? 'Could not create the $_noun.' : 'Could not save your change.') : e.message);
      setState(() {
        _saving = false;
        _formError = msg;
      });
      ref.read(toastProvider.notifier).showError(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    // No id → this form is creating rather than editing. Same schema, same
    // widget; only the write and the empty starting values differ.
    final creating = id.isEmpty;
    // Independent field configs — a follow-up's layout is not a task's.
    final schema = widget.isFollowup
        ? ref.watch(followupDetailSchemaProvider)
        : ref.watch(taskDetailSchemaProvider);
    // One record endpoint for both: a follow-up *is* a task. A create has no
    // record to wait for, so it starts from an empty row.
    final row = creating
        ? const AsyncValue<Map<String, dynamic>?>.data(<String, dynamic>{})
        : ref.watch(_rowProvider(id));

    // The pickers read these; watched here so they are loading by the time the
    // user opens one rather than starting on first tap.
    final statuses = ref.watch(taskStatusOptionsProvider);
    ref.watch(taskPriorityOptionsProvider);
    ref.watch(teamOptionsProvider);
    final defaults = ref.watch(taskFormDefaultsProvider).valueOrNull;
    final users = ref.watch(assignableUsersForModuleProvider(widget.isFollowup ? 'followup' : 'task')).valueOrNull;

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: widget.isFollowup ? 'Follow-up' : 'Task',
            name: switch ((creating, widget.isFollowup)) {
              (true, true) => 'New follow-up',
              (true, false) => 'New task',
              (false, true) => 'Edit follow-up',
              (false, false) => 'Edit task',
            },
            onBack: () => context.pop(),
          ),
          Expanded(
            child: switch (row) {
              AsyncValue(hasError: true) => Center(
                  child: Text('Could not load this $_noun',
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
                    else ...[
                      if (creating && !widget.isFollowup) ...[_relatedPicker(), SizedBox(height: 14.h)],
                      LeadSchemaForm(
                        key: _formKey,
                        schema: schema,
                        row: row.valueOrNull,
                        includeCustomFields: true,
                        alwaysSendCustomBooleans: true,
                        hiddenColumns: const {'committed_due_date'},
                        onValueChanged: _onFormChanged,
                        initialChoices: creating && defaults != null
                            ? {
                                if (defaults.status != null) 'status': defaults.status!,
                                if (defaults.priority != null) 'priority': defaults.priority!,
                              }
                            : const {},
                        // `task_type` is typed `string` in the schema but is
                        // really a choice — the org's own type list, which no
                        // `related_model` names. Without these it renders as a
                        // free-text box and a typo is a rejected save.
                        optionsByColumn: {
                          'task_type': widget.isFollowup
                              ? ref.watch(followupTypeOptionsProvider)
                              : ref.watch(taskTypeOptionsProvider),
                          // Webapp: a new task starts only in an open lane.
                          if (creating && defaults != null && defaults.creatable.isNotEmpty)
                            'status': [for (final s in statuses) if (defaults.creatable.contains(s.id)) s],
                          // The users the server lets own a task — not the
                          // whole roster.
                          if (users != null && users.isNotEmpty) ...{
                            'assigned_to': users,
                            'assignees': users,
                          },
                        },
                      ),
                      if (creating && _overdue)
                        Padding(
                          padding: EdgeInsets.only(top: 6.h),
                          child: Text('This task will be overdue — ${_dmy(DateTime.parse(_dueIso))} has already passed.',
                              style: AppText.caption(color: AppColors.warningDeep)),
                        ),
                      if (creating && !widget.isFollowup) _meetingSection(),
                      if (_formError != null)
                        Padding(
                          padding: EdgeInsets.only(top: 12.h),
                          child: Text(_formError!, style: AppText.caption(color: AppColors.error)),
                        ),
                    ],
                  ],
                ),
            },
          ),
          _actionBar(id),
        ],
      ),
    );
  }

  // ── Related to (webapp RelatedRecordPicker) ──
  Widget _relatedPicker() {
    final lead = _relatedKind == 'lead';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SheetFieldLabel('Related to'),
      Wrap(spacing: 8.w, children: [
        for (final k in const ['lead', 'customer'])
          SelectChip(
            label: k == 'lead' ? 'Lead' : 'Customer',
            selected: _relatedKind == k,
            onTap: () => setState(() {
              if (_relatedKind != k) _related = null;
              _relatedKind = k;
            }),
          ),
      ]),
      SizedBox(height: 8.h),
      AppTextField(
        label: lead ? 'Lead' : 'Customer',
        readOnly: true,
        value: _related?.label ?? '',
        hint: lead ? 'Search leads by name, company, email or phone…' : 'Search customers by name, company, email…',
        suffixIcon: _related == null ? PhosphorIconsRegular.magnifyingGlass : PhosphorIconsRegular.x,
        onTap: () async {
          FocusManager.instance.primaryFocus?.unfocus();
          if (_related != null) {
            setState(() => _related = null);
            return;
          }
          final picked = await showModalBottomSheet<({String id, String label})>(
            context: context,
            isScrollControlled: true,
            builder: (_) => RecordSearchSheet(kind: _relatedKind),
          );
          if (picked != null && mounted) setState(() => _related = picked);
        },
      ),
      Padding(
        padding: EdgeInsets.only(top: 6.h, left: 2.w),
        child: Text("Optional — shows on that record's activity.", style: AppText.caption()),
      ),
    ]);
  }

  // ── Meeting (webapp "Add meeting time & location") ──
  Widget _meetingSection() {
    if (!_meetingOpen) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _meetingOpen = true),
          icon: Icon(PhosphorIconsRegular.mapPin, size: 15.sp),
          label: const Text('Add meeting time & location'),
        ),
      );
    }
    Future<DateTime?> pick(DateTime? current) async {
      FocusManager.instance.primaryFocus?.unfocus();
      final d = await pickSheetDate(context, current == null ? '' : sheetIsoDate(current));
      if (d == null || !mounted) return null;
      final t = await pickSheetTime(context, current == null ? '' : sheetTimeLabel(TimeOfDay.fromDateTime(current)));
      final time = t ?? const TimeOfDay(hour: 9, minute: 0);
      return DateTime(d.year, d.month, d.day, time.hour, time.minute);
    }

    String show(DateTime? d) => d == null ? '' : '${sheetDateLabel(d)} · ${sheetTimeLabel(TimeOfDay.fromDateTime(d))}';
    return Padding(
      padding: EdgeInsets.only(top: 14.h),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppTextField(
          label: 'Meeting start',
          readOnly: true,
          value: show(_meetingFrom),
          hint: 'Select meeting start…',
          suffixIcon: PhosphorIconsRegular.calendarBlank,
          onTap: () async {
            final d = await pick(_meetingFrom);
            if (d != null) setState(() => _meetingFrom = d);
          },
        ),
        SizedBox(height: 14.h),
        AppTextField(
          label: 'Meeting end',
          readOnly: true,
          value: show(_meetingTo),
          hint: 'Select meeting end…',
          errorText: _meetingError,
          suffixIcon: PhosphorIconsRegular.calendarBlank,
          onTap: () async {
            final d = await pick(_meetingTo ?? _meetingFrom);
            if (d != null) {
              setState(() {
                _meetingTo = d;
                _meetingError = null;
              });
            }
          },
        ),
        SizedBox(height: 14.h),
        AppTextField(label: 'Location', controller: _location, hint: 'e.g. Client office, Zoom link'),
      ]),
    );
  }

  Widget _actionBar(String id) {
    final creating = id.isEmpty;
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
                          Text(creating ? 'Add $_noun' : 'Save changes',
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

/// Search a lead or customer to link (webapp RelatedRecordPicker): debounced
/// 300 ms, first 20 matches.
class RecordSearchSheet extends ConsumerStatefulWidget {
  const RecordSearchSheet({super.key, required this.kind});

  final String kind;

  @override
  ConsumerState<RecordSearchSheet> createState() => _RecordSearchSheetState();
}

class _RecordSearchSheetState extends ConsumerState<RecordSearchSheet> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<({String id, String label, String sub})>? _rows;

  bool get _lead => widget.kind == 'lead';

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    try {
      final body = await ref.read(apiServiceProvider).get(
        _lead ? ApiEndpoints.leads : ApiEndpoints.customers,
        query: {if (q.isNotEmpty) 'search': q, 'page': 1, 'page_size': 20},
        quiet: true,
      );
      String first(Map r, List<String> keys) {
        for (final k in keys) {
          final v = '${r[k] ?? ''}'.trim();
          if (v.isNotEmpty && v != 'null') return v;
        }
        return '';
      }

      final rows = [
        for (final r in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results)
          (
            id: '${r[_lead ? 'lead_id' : 'customer_id'] ?? r['id'] ?? ''}',
            label: _lead
                ? first(r, const ['lead_name', 'name', 'company', 'company_name', 'full_name', 'email'])
                : first(r, const ['name', 'customer_name', 'company', 'company_name', 'contact_name', 'email']),
            sub: first(r, const ['reference']),
          ),
      ];
      if (mounted) setState(() => _rows = rows);
    } on Object {
      if (mounted) setState(() => _rows = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    final noun = _lead ? 'leads' : 'customers';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: EdgeInsets.all(16.r),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _search);
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: _lead ? 'Search leads by name, company, email or phone…' : 'Search customers by name, company, email…',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _rows == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _rows!.isEmpty
                    ? Center(child: Text(q.isEmpty ? 'No $noun yet' : 'No $noun match “$q”', style: AppText.body(color: AppColors.textMuted)))
                    : ListView(children: [
                        for (final r in _rows!)
                          if (r.id.isNotEmpty)
                            ListTile(
                              title: Text(r.label, style: AppText.bodyStrong()),
                              subtitle: r.sub.isEmpty ? null : Text(r.sub),
                              onTap: () => Navigator.of(context).pop((id: r.id, label: r.label)),
                            ),
                      ]),
          ),
        ]),
      ),
    );
  }
}
