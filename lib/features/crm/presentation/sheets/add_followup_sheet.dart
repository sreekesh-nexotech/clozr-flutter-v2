import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/followups_filter_spec.dart';
import '../../application/followup_form_rules.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/followup_form_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/crm_catalog.dart';
import '../components/option_picker_sheet.dart';
import '../screens/edit_crm_task_screen.dart' show RecordSearchSheet, taskFormDefaultsProvider;
import 'add_sheet_kit.dart';
import 'linked_record_banner.dart';

/// New follow-up — the webapp's Add follow-up form (`AddTaskModal` with
/// `isFollowup`) as a sheet (UAT CRM-FU-013).
///
/// Like the webapp, this is a FIXED field set, not the follow-up layout
/// schema: Title, Related to, Type, Status, Due date, Due time, Reminder,
/// Priority, Team, Assign to, Additional assignees, the meeting window +
/// Location, Description, then the task custom fields that apply to
/// follow-ups. Labels, hints, validation messages and the request body follow
/// the webapp; the rules live in `followup_form_rules.dart`.
///
/// Pass [lead] when opening from a lead's Follow-ups tab, or [customer] (id +
/// display name) from a customer's: the link is then fixed — the sheet shows
/// "Linked to <name>" instead of the Related to picker — and the follow-up
/// carries `related_to` / `related_to_id` for it.
Future<void> showAddFollowupSheet(BuildContext context, WidgetRef ref,
    {Lead? lead, ({String id, String label})? customer}) async {
  // The option catalogs are awaited briefly so the pickers open on the org's
  // own types / statuses / priorities rather than filling in under the user.
  try {
    await Future.wait([
      ref.read(followupTypeCatalogProvider.future),
      ref.read(taskStatusCatalogProvider.future),
      ref.read(taskPriorityCatalogProvider.future),
    ]).timeout(const Duration(seconds: 6));
  } on Object {
    // Slow or failed — open with whatever has arrived.
  }
  if (!context.mounted) return;
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _AddFollowupSheet(lead: lead, customer: lead == null ? customer : null),
  );
}

/// Picker id standing for "no value" (Unassigned / No team / No reminder / None).
const _none = '__none__';

class _AddFollowupSheet extends ConsumerStatefulWidget {
  const _AddFollowupSheet({this.lead, this.customer});

  /// The lead this follow-up is being scheduled against, when opened from one.
  final Lead? lead;

  /// The customer this follow-up is being scheduled against, when opened from one.
  final ({String id, String label})? customer;

  @override
  ConsumerState<_AddFollowupSheet> createState() => _AddFollowupSheetState();
}

class _AddFollowupSheetState extends ConsumerState<_AddFollowupSheet> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();

  /// Related to (only when the caller did not fix the link): `lead` |
  /// `customer`, and the picked record.
  String _relatedKind = 'lead';
  ({String id, String label})? _related;

  // `null` = untouched: the field shows (and saves) its default — the first
  // type, the org's default status / priority — until the user picks another.
  String? _typeChoice;
  String? _statusChoice;
  String? _priorityChoice;

  String _assignee = '';
  final List<String> _extraAssignees = [];
  String _teamId = '';
  DateTime? _dueDate;
  String _dueTime = '';
  String _reminder = '';
  bool _meetingOpen = false;
  DateTime? _meetingFrom;
  DateTime? _meetingTo;

  /// Custom-field values by field name (String / List<String> / bool), and
  /// the controllers of the typed ones.
  final Map<String, Object?> _customDrafts = {};
  final Map<String, TextEditingController> _customCtrls = {};

  /// Field errors: `dueDate`, `reminder`, `meetingTo`, `custom_fields.<name>`.
  Map<String, String> _errors = const {};
  final Map<String, GlobalKey> _errorAnchors = {};
  String? _formError;

  /// True while the create is in flight, so a second tap cannot post again.
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _location, _description, ..._customCtrls.values]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── resolved options (watched in build, read here) ──

  /// The org's follow-up types by name — a follow-up's `task_type` is written
  /// by name. Mock mode (no API) falls back to the built-in vocabulary.
  List<String> get _types {
    final catalog = ref.read(followupTypeOptionsProvider);
    if (catalog.isNotEmpty) return [for (final t in catalog) t.name];
    return ApiConfig.apiEnabled ? const [] : kBuiltinFollowupTypes;
  }

  String get _type {
    final types = _types;
    final choice = _typeChoice;
    if (choice != null && types.contains(choice)) return choice;
    return types.isEmpty ? '' : types.first;
  }

  ({String? status, String? priority, Set<String> creatable})? get _defaults =>
      ref.read(taskFormDefaultsProvider).valueOrNull;

  /// Webapp `creatableStatuses`: a new follow-up starts only in an open lane.
  List<CatalogOption> get _statusOptions {
    final all = ref.read(taskStatusOptionsProvider);
    final creatable = _defaults?.creatable ?? const <String>{};
    if (creatable.isNotEmpty) return [for (final s in all) if (creatable.contains(s.id)) s];
    return [for (final s in all) if (s.statusType != 'completed' && s.statusType != 'cancelled') s];
  }

  String get _statusId => _statusChoice ?? _defaults?.status ?? '';
  List<CatalogOption> get _priorityOptions => ref.read(taskPriorityOptionsProvider);
  String get _priorityId => _priorityChoice ?? _defaults?.priority ?? '';
  List<CatalogOption> get _users => ref.read(assignableUsersForModuleProvider('followup')).valueOrNull ?? const [];
  List<CatalogOption> get _teams => ref.read(assignableTeamsForModuleProvider('followup')).valueOrNull ?? const [];

  AsyncValue<List<TaskCustomFieldDef>> get _customAsync => ref.read(taskCustomFieldDefsProvider);

  /// The custom fields that belong on a follow-up (`all` + `followup`).
  List<TaskCustomFieldDef> get _customDefs =>
      customFieldsForKind(_customAsync.valueOrNull ?? const [], isFollowup: true);

  bool get _linkFixed => widget.lead != null || widget.customer != null;

  String _nameOf(List<CatalogOption> options, String id, {String fallback = ''}) =>
      options.where((o) => o.id == id).firstOrNull?.name ?? fallback;

  FollowupDraft get _draft {
    final lead = widget.lead;
    final customer = widget.customer;
    final (relatedTo, relatedToId) = lead != null
        ? ('lead', lead.id)
        : customer != null
            ? ('customer', customer.id)
            : _related != null
                ? (_relatedKind, _related!.id)
                : ('', '');
    return FollowupDraft(
      title: _title.text,
      type: _type,
      statusId: _statusId,
      priorityId: _priorityId,
      assignedTo: _assignee,
      extraAssignees: List.of(_extraAssignees),
      teamId: _teamId,
      dueDate: _dueDate,
      dueTime: _dueTime,
      reminder: _reminder,
      meetingFrom: _meetingFrom,
      meetingTo: _meetingTo,
      location: _location.text,
      description: _description.text,
      relatedTo: relatedTo,
      relatedToId: relatedToId,
    );
  }

  /// Webapp `canSave`: a title, a type, and the custom fields known — or a
  /// required one is skipped again.
  bool get _canSave => followupCanSave(_draft) && !_customAsync.isLoading && !_saving;

  bool get _showMeeting =>
      _meetingOpen || isMeetingType(_type) || _meetingFrom != null || _meetingTo != null || _location.text.isNotEmpty;

  void _clearError(String key) {
    if (!_errors.containsKey(key)) return;
    setState(() => _errors = {..._errors}..remove(key));
  }

  GlobalKey _anchor(String key) => _errorAnchors.putIfAbsent(key, GlobalKey.new);

  // ── save ──

  Future<void> _save({bool overdueConfirmed = false}) async {
    if (!_canSave) return;
    final defs = _customDefs;
    final draft = _draft;
    final found = followupFormErrors(draft, defs, _customDrafts);
    final toast = ref.read(toastProvider.notifier);
    if (found.isNotEmpty) {
      setState(() {
        _errors = found;
        _formError = null;
      });
      toast.showError(found.values.first);
      // Bring the first bad field into view — a required custom field sits at
      // the bottom of a long sheet.
      final ctx = _errorAnchors[found.keys.first]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 250));
      }
      return;
    }
    // TK-04: a past due date is allowed, but only on purpose.
    if (!overdueConfirmed && isPastDueDate(draft.dueDate)) {
      final when = followupDayLabel(draft.dueDate!);
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Create an overdue follow-up?'),
          content: Text('The due date $when has already passed, so this follow-up will be overdue as soon as it is created.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Change date')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create follow-up')),
          ],
        ),
      );
      if (go != true || !mounted) return;
      return _save(overdueConfirmed: true);
    }

    final body = buildFollowupCreateBody(draft, collectCustomFields(defs, _customDrafts).values);
    setState(() {
      _errors = const {};
      _formError = null;
      _saving = true;
    });
    try {
      if (ApiConfig.apiEnabled) {
        await ref.read(followupsRepositoryProvider).createFollowupFields(body);
      } else {
        _addMockDraft(draft);
      }
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(apiServiceProvider).handled(e);
      // Keep the message in the form too — the toast fades while the user
      // fixes it (webapp). Field errors the form has a slot for go under it.
      const slots = {'due_date': 'dueDate', 'reminder_choice': 'reminder', 'meeting_to': 'meetingTo', 'meeting_from': 'meetingTo'};
      final inline = {
        for (final f in (e.fieldErrors ?? const <String, List<String>>{}).entries)
          if (f.value.isNotEmpty && slots.containsKey(f.key)) slots[f.key]!: f.value.first,
      };
      final msg = e.bareMessage.isEmpty ? 'Could not create the follow-up.' : e.bareMessage;
      setState(() {
        _errors = inline;
        _formError = msg;
        _saving = false;
      });
      toast.showError(msg);
      return;
    } on Object {
      // Never leave the button stuck on "Saving…".
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
    if (!mounted) return;
    refreshFollowups(ref);
    // Every lead's Follow-ups tab reads its own scoped fetch.
    ref.invalidate(leadFollowupsProvider);
    toast.show('Follow-up created');
    Navigator.of(context).pop();
  }

  /// Mock mode (no API): the follow-up goes straight into the local drafts.
  void _addMockDraft(FollowupDraft d) {
    final contact = widget.lead?.name ?? widget.customer?.label ?? _related?.label ?? d.title.trim();
    final fu = Followup(
      id: genId('F'),
      kind: d.type,
      contact: contact,
      custId: null,
      leadId: widget.lead?.id,
      company: widget.lead?.company ?? contact,
      due: d.dueDate == null ? '' : sheetDateLabel(d.dueDate!),
      time: d.dueTime,
      status: 'due',
      owner: 'me',
      title: d.title.trim(),
      description: d.description.trim(),
    );
    ref.read(followupDraftsProvider.notifier).state = [fu, ...ref.read(followupDraftsProvider)];
  }

  // ── pickers ──

  Future<String?> _pickOne(String title, List<CatalogOption> options, String selected) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showOptionPicker(
      context: context,
      title: title,
      options: options,
      selected: {selected.isEmpty ? _none : selected},
    );
    if (picked == null || picked.isEmpty || !mounted) return null;
    return picked.first == _none ? '' : picked.first;
  }

  Future<void> _pickDueDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final max = followupDueDateMax(now);
    var initial = _dueDate ?? now;
    if (initial.isBefore(followupDueDateMin)) initial = followupDueDateMin;
    if (initial.isAfter(max)) initial = max;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: followupDueDateMin, lastDate: max);
    if (picked == null || !mounted) return;
    setState(() {
      _dueDate = picked;
      _errors = {..._errors}
        ..remove('dueDate')
        ..remove('reminder');
    });
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final d = await pickSheetDate(context, current == null ? '' : sheetIsoDate(current));
    if (d == null || !mounted) return null;
    final t = await pickSheetTime(context, current == null ? '' : sheetTimeLabel(TimeOfDay.fromDateTime(current)));
    final time = t ?? const TimeOfDay(hour: 9, minute: 0);
    return DateTime(d.year, d.month, d.day, time.hour, time.minute);
  }

  String _dateTimeLabel(DateTime? d) =>
      d == null ? '' : '${sheetDateLabel(d)} · ${sheetTimeLabel(TimeOfDay.fromDateTime(d))}';

  @override
  Widget build(BuildContext context) {
    // Subscribed here; the getters above read the current values.
    ref.watch(followupTypeOptionsProvider);
    ref.watch(taskStatusOptionsProvider);
    ref.watch(taskPriorityOptionsProvider);
    ref.watch(taskFormDefaultsProvider);
    ref.watch(assignableUsersForModuleProvider('followup'));
    ref.watch(assignableTeamsForModuleProvider('followup'));
    ref.watch(taskCustomFieldDefsProvider);

    final type = _type;
    final statusOptions = _statusOptions;
    final statusId = _statusId;
    final priorityId = _priorityId;
    final linkLabel = widget.lead?.name ?? widget.customer?.label;
    final dueError = followupDueDateError(_dueDate);
    final overdue = dueError == null && isPastDueDate(_dueDate);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'New follow-up', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: SingleChildScrollView(
            // Typing in a field must not trap the keyboard over the rest.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (linkLabel != null) ...[
                  LinkedRecordBanner(label: linkLabel),
                  SizedBox(height: 16.h),
                ],
                AppTextField(
                  label: 'Title',
                  required: true,
                  controller: _title,
                  hint: 'e.g. Follow up on quote',
                  inputFormatters: [LengthLimitingTextInputFormatter(followupTitleMax)],
                  onChanged: (_) => setState(() {}),
                ),
                if (!_linkFixed) ...[
                  SizedBox(height: 14.h),
                  _relatedPicker(),
                ],
                SizedBox(height: 14.h),
                _row(
                  _PickerField(
                    label: 'Type',
                    required: true,
                    value: type,
                    hint: 'Select type',
                    onTap: () async {
                      final v = await _pickOne('Type', [for (final t in _types) CatalogOption(id: t, name: t)], type);
                      if (v != null && v.isNotEmpty) setState(() => _typeChoice = v);
                    },
                  ),
                  _PickerField(
                    label: 'Status',
                    value: _nameOf(statusOptions, statusId),
                    hint: 'Org default',
                    dot: statusOptions.where((s) => s.id == statusId).firstOrNull?.color,
                    onTap: () async {
                      final v = await _pickOne('Status', statusOptions, statusId);
                      if (v != null && v.isNotEmpty) setState(() => _statusChoice = v);
                    },
                  ),
                ),
                SizedBox(height: 14.h),
                _row(
                  KeyedSubtree(
                    key: _anchor('dueDate'),
                    child: _PickerField(
                      label: 'Due date',
                      value: _dueDate == null ? '' : sheetDateLabel(_dueDate!),
                      hint: 'Select date',
                      icon: PhosphorIconsRegular.calendarBlank,
                      error: _errors['dueDate'] ?? dueError,
                      onTap: _pickDueDate,
                      onClear: _dueDate == null
                          ? null
                          : () => setState(() {
                                _dueDate = null;
                                _errors = {..._errors}
                                  ..remove('dueDate')
                                  ..remove('reminder');
                              }),
                    ),
                  ),
                  _PickerField(
                    label: 'Due time',
                    value: _dueDate == null ? '' : _dueTime,
                    hint: _dueDate == null ? '--:--' : 'Select time',
                    icon: PhosphorIconsRegular.clock,
                    enabled: _dueDate != null,
                    helper: _dueDate == null ? 'Set a due date first' : null,
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final t = await pickSheetTime(context, _dueTime);
                      if (t != null && mounted) setState(() => _dueTime = sheetTimeLabel(t));
                    },
                    onClear: _dueTime.isEmpty || _dueDate == null ? null : () => setState(() => _dueTime = ''),
                  ),
                ),
                SizedBox(height: 14.h),
                KeyedSubtree(
                  key: _anchor('reminder'),
                  child: _PickerField(
                    label: 'Reminder',
                    value: reminderLabel(_reminder),
                    icon: PhosphorIconsRegular.bellSimple,
                    error: _errors['reminder'],
                    onTap: () async {
                      final v = await _pickOne(
                        'Reminder',
                        [
                          const CatalogOption(id: _none, name: 'No reminder'),
                          for (final (v, l) in followupReminderOptions) CatalogOption(id: v, name: l),
                        ],
                        _reminder,
                      );
                      if (v == null) return;
                      setState(() => _reminder = v);
                      _clearError('reminder');
                    },
                  ),
                ),
                if (overdue)
                  Padding(
                    padding: EdgeInsets.only(top: 8.h),
                    child: Row(children: [
                      Icon(PhosphorIconsRegular.warning, size: 14.sp, color: AppColors.warningDeep),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text('This follow-up will be overdue — ${followupDayLabel(_dueDate!)} has already passed.',
                            style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.warningDeep)),
                      ),
                    ]),
                  ),
                SizedBox(height: 14.h),
                _row(
                  _PickerField(
                    label: 'Priority',
                    value: _nameOf(_priorityOptions, priorityId),
                    hint: 'Select priority',
                    onTap: () async {
                      final v = await _pickOne('Priority', _priorityOptions, priorityId);
                      if (v != null && v.isNotEmpty) setState(() => _priorityChoice = v);
                    },
                  ),
                  _PickerField(
                    label: 'Team',
                    value: _nameOf(_teams, _teamId, fallback: 'No team'),
                    onTap: () async {
                      final v = await _pickOne(
                          'Team', [const CatalogOption(id: _none, name: 'No team'), ..._teams], _teamId);
                      if (v != null) setState(() => _teamId = v);
                    },
                  ),
                ),
                SizedBox(height: 14.h),
                _PickerField(
                  label: 'Assign to',
                  value: _nameOf(_users, _assignee, fallback: _assignee.isEmpty ? 'Unassigned' : 'User'),
                  helper: 'The primary owner — always part of the assignee set.',
                  onTap: () async {
                    final v = await _pickOne(
                        'Assign to', [const CatalogOption(id: _none, name: 'Unassigned'), ..._users], _assignee);
                    if (v == null) return;
                    setState(() {
                      _assignee = v;
                      // The primary is never also an extra (no duplicate chip).
                      if (v.isNotEmpty) _extraAssignees.remove(v);
                    });
                  },
                ),
                SizedBox(height: 14.h),
                _additionalAssignees(),
                SizedBox(height: 14.h),
                _meetingSection(),
                SizedBox(height: 14.h),
                AppTextField(
                  label: 'Description',
                  controller: _description,
                  multiline: true,
                  hint: 'What is this follow-up about?',
                ),
                _customFieldsSection(),
                if (_formError != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12.h),
                    child: Text(_formError!, style: AppText.caption(color: AppColors.error)),
                  ),
              ],
            ),
          ),
        ),
        // Webapp: the button stays disabled until there is a title and a type.
        IgnorePointer(
          ignoring: !_canSave && !_saving,
          child: Opacity(
            opacity: _canSave || _saving ? 1 : 0.5,
            child: SheetSubmitBar(
              label: 'Add follow-up',
              icon: PhosphorIconsBold.plus,
              busy: _saving,
              busyLabel: 'Saving…',
              onTap: _save,
            ),
          ),
        ),
      ],
    );
  }

  /// Two fields side by side (the webapp's two-column grid).
  Widget _row(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: a), SizedBox(width: 10.w), Expanded(child: b)],
      );

  // ── Related to (webapp RelatedRecordPicker) ──
  Widget _relatedPicker() {
    final lead = _relatedKind == 'lead';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SheetFieldLabel('Related to'),
      Wrap(spacing: 8.w, children: [
        for (final k in const ['lead', 'customer'])
          SelectChip(
            label: k == 'lead' ? 'Lead' : 'Customer',
            icon: k == 'lead' ? PhosphorIconsRegular.user : PhosphorIconsRegular.buildings,
            selected: _relatedKind == k,
            onTap: () => setState(() {
              // Switching the model clears the pick — a link is to one record.
              if (_relatedKind != k) _related = null;
              _relatedKind = k;
            }),
          ),
      ]),
      SizedBox(height: 8.h),
      _PickerField(
        label: lead ? 'Lead' : 'Customer',
        value: _related?.label ?? '',
        hint: lead ? 'Search leads by name, company, email or phone…' : 'Search customers by name, company, email…',
        icon: PhosphorIconsRegular.magnifyingGlass,
        helper: "Optional — shows on that record's activity.",
        onClear: _related == null ? null : () => setState(() => _related = null),
        onTap: () async {
          FocusManager.instance.primaryFocus?.unfocus();
          final picked = await showModalBottomSheet<({String id, String label})>(
            context: context,
            isScrollControlled: true,
            builder: (_) => RecordSearchSheet(kind: _relatedKind),
          );
          if (picked != null && mounted) setState(() => _related = picked);
        },
      ),
    ]);
  }

  // ── Additional assignees (chips + "Add an assignee…") ──
  Widget _additionalAssignees() {
    final users = _users;
    String label(String id) => _nameOf(users, id, fallback: 'User');
    final addable = [for (final u in users) if (u.id != _assignee && !_extraAssignees.contains(u.id)) u];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_extraAssignees.isNotEmpty) ...[
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final id in _extraAssignees)
            Container(
              padding: EdgeInsets.fromLTRB(6.w, 4.h, 8.w, 4.h),
              decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 20.w,
                  height: 20.w,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                  child: Text(initialsOf(label(id)),
                      style: AppText.custom(size: 9, weight: FontWeight.w700, color: AppColors.white)),
                ),
                SizedBox(width: 7.w),
                Text(label(id), style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPrimary)),
                SizedBox(width: 4.w),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _extraAssignees.remove(id)),
                  child: Semantics(
                    label: 'Remove ${label(id)}',
                    child: Icon(PhosphorIconsRegular.x, size: 13.sp, color: AppColors.textMuted),
                  ),
                ),
              ]),
            ),
        ]),
        SizedBox(height: 8.h),
      ],
      _PickerField(
        label: 'Additional assignees',
        value: '',
        hint: addable.isNotEmpty ? 'Add an assignee…' : 'No more users',
        enabled: addable.isNotEmpty,
        onTap: () async {
          final v = await _pickOne('Additional assignees', addable, '');
          if (v != null && v.isNotEmpty && !_extraAssignees.contains(v)) setState(() => _extraAssignees.add(v));
        },
      ),
    ]);
  }

  // ── Meeting (webapp "Add meeting time & location") ──
  Widget _meetingSection() {
    if (!_showMeeting) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _meetingOpen = true),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(PhosphorIconsRegular.calendarPlus, size: 15.sp, color: AppColors.navy),
          SizedBox(width: 7.w),
          Text('Add meeting time & location',
              style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.navy)),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _PickerField(
        label: 'Meeting start',
        value: _dateTimeLabel(_meetingFrom),
        hint: 'Select meeting start…',
        icon: PhosphorIconsRegular.calendarBlank,
        onTap: () async {
          final d = await _pickDateTime(_meetingFrom);
          if (d != null) setState(() => _meetingFrom = d);
          _clearError('meetingTo');
        },
        onClear: _meetingFrom == null
            ? null
            : () {
                setState(() => _meetingFrom = null);
                _clearError('meetingTo');
              },
      ),
      SizedBox(height: 14.h),
      KeyedSubtree(
        key: _anchor('meetingTo'),
        child: _PickerField(
          label: 'Meeting end',
          value: _dateTimeLabel(_meetingTo),
          hint: 'Select meeting end…',
          icon: PhosphorIconsRegular.calendarBlank,
          error: _errors['meetingTo'],
          onTap: () async {
            final d = await _pickDateTime(_meetingTo ?? _meetingFrom);
            if (d != null) setState(() => _meetingTo = d);
            _clearError('meetingTo');
          },
          onClear: _meetingTo == null
              ? null
              : () {
                  setState(() => _meetingTo = null);
                  _clearError('meetingTo');
                },
        ),
      ),
      SizedBox(height: 14.h),
      AppTextField(
        label: 'Location',
        controller: _location,
        hint: 'e.g. Client office, Zoom link',
        inputFormatters: [LengthLimitingTextInputFormatter(followupLocationMax)],
        onChanged: (_) => setState(() {}),
      ),
    ]);
  }

  // ── Custom fields (webapp CF-01) ──
  Widget _customFieldsSection() {
    final async = _customAsync;
    final hint = AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder);
    if (async.isLoading) {
      return Padding(padding: EdgeInsets.only(top: 14.h), child: Text('Loading custom fields…', style: hint));
    }
    if (async.hasError) {
      // The server still checks required fields; say why its message may name one.
      return Padding(
        padding: EdgeInsets.only(top: 14.h),
        child: Text('Custom fields could not be loaded — required ones are checked when you save.', style: hint),
      );
    }
    final defs = _customDefs;
    if (defs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 18.h),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CUSTOM FIELDS',
            style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder)
                .copyWith(letterSpacing: 0.55)),
        for (final def in defs) ...[
          SizedBox(height: 12.h),
          KeyedSubtree(key: _anchor(customErrorKey(def.name)), child: _customField(def)),
        ],
      ]),
    );
  }

  void _setCustom(String name, Object? value) {
    setState(() => _customDrafts[name] = value);
    _clearError(customErrorKey(name));
  }

  Widget _customField(TaskCustomFieldDef def) {
    final error = _errors[customErrorKey(def.name)];
    final draft = _customDrafts[def.name] ?? emptyCustomDraft(def);
    final text = draft is String ? draft : '';
    switch (def.type) {
      case 'boolean':
        final on = draft == true;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setCustom(def.name, !on),
            child: Row(children: [
              SizedBox(
                width: 24.w,
                height: 24.w,
                child: Checkbox(value: on, onChanged: (v) => _setCustom(def.name, v == true)),
              ),
              SizedBox(width: 8.w),
              Flexible(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: def.label),
                  if (def.required) TextSpan(text: ' *', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.error)),
                ]), style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ]),
          ),
          if (error != null) _errorText(error),
        ]);
      case 'dropdown':
        return _PickerField(
          label: def.label,
          required: def.required,
          value: text,
          hint: 'Select…',
          error: error,
          onTap: () async {
            final v = await _pickOne(def.label, [
              // An optional field can be cleared again; a required one starts blank.
              if (!def.required) const CatalogOption(id: _none, name: 'None'),
              for (final c in def.choices) CatalogOption(id: c, name: c),
            ], text);
            if (v != null) _setCustom(def.name, v);
          },
        );
      case 'multi_select':
        final selected = draft is List ? [for (final v in draft) '$v'] : <String>[];
        return _PickerField(
          label: def.label,
          required: def.required,
          value: selected.join(', '),
          hint: 'Select…',
          error: error,
          onTap: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            final picked = await showOptionPicker(
              context: context,
              title: def.label,
              options: [for (final c in def.choices) CatalogOption(id: c, name: c)],
              selected: selected.toSet(),
              multi: true,
            );
            if (picked == null || !mounted) return;
            // Kept in the admin's option order.
            _setCustom(def.name, [for (final c in def.choices) if (picked.contains(c)) c]);
          },
        );
      case 'date':
        final day = DateTime.tryParse(text);
        return _PickerField(
          label: def.label,
          required: def.required,
          value: day == null ? '' : sheetDateLabel(day),
          hint: 'Select date',
          icon: PhosphorIconsRegular.calendarBlank,
          error: error,
          onTap: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            final d = await pickSheetDate(context, text);
            if (d != null && mounted) _setCustom(def.name, isoDay(d));
          },
          onClear: text.isEmpty ? null : () => _setCustom(def.name, ''),
        );
      case 'datetime':
        final at = DateTime.tryParse(text);
        return _PickerField(
          label: def.label,
          required: def.required,
          value: _dateTimeLabel(at),
          hint: 'Select date & time',
          icon: PhosphorIconsRegular.calendarBlank,
          error: error,
          onTap: () async {
            final d = await _pickDateTime(at);
            if (d == null || !mounted) return;
            // `datetime-local` wall time, as the webapp sends it.
            _setCustom(def.name, '${isoDay(d)}T${sheetTimeLabel(TimeOfDay.fromDateTime(d))}');
          },
          onClear: text.isEmpty ? null : () => _setCustom(def.name, ''),
        );
      default:
        final ctrl = _customCtrls.putIfAbsent(def.name, () => TextEditingController(text: text));
        return AppTextField(
          label: def.label,
          required: def.required,
          controller: ctrl,
          multiline: def.type == 'textarea',
          hint: def.type == 'url' ? 'https://' : null,
          errorText: error,
          keyboardType: switch (def.type) {
            'number' => TextInputType.number,
            'decimal' => const TextInputType.numberWithOptions(decimal: true, signed: true),
            'email' => TextInputType.emailAddress,
            'phone' => TextInputType.phone,
            'url' => TextInputType.url,
            'textarea' => TextInputType.multiline,
            _ => TextInputType.text,
          },
          inputFormatters: def.type == 'text' ? [LengthLimitingTextInputFormatter(customTextMax)] : null,
          onChanged: (v) {
            _customDrafts[def.name] = v;
            _clearError(customErrorKey(def.name));
          },
        );
    }
  }
}

Widget _errorText(String text) => Padding(
      padding: EdgeInsets.only(top: 5.h),
      child: Text(text, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.error)),
    );

/// A labelled picker trigger in the [AppTextField] style, with what the
/// webapp's selects and date inputs have and that one lacks: a disabled state,
/// a hint line under the box, a status dot and a clear button.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
    this.required = false,
    this.enabled = true,
    this.error,
    this.helper,
    this.icon,
    this.dot,
    this.onClear,
  });

  final String label;
  final String value;
  final String? hint;
  final bool required;
  final bool enabled;
  final String? error;
  final String? helper;
  final IconData? icon;
  final Color? dot;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final filled = value.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
        ),
        if (required) Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
      ]),
      SizedBox(height: 7.h),
      Opacity(
        opacity: enabled ? 1 : 0.6,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: BoxConstraints(minHeight: 44.h),
            padding: EdgeInsets.symmetric(horizontal: 13.w),
            decoration: BoxDecoration(
              color: enabled ? AppColors.white : AppColors.bgChipGrey,
              borderRadius: BorderRadius.circular(11.r),
              border: Border.all(color: error != null ? AppColors.error : AppColors.borderInput, width: 1.5),
            ),
            child: Row(children: [
              if (dot != null && filled) ...[
                Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                SizedBox(width: 7.w),
              ],
              Expanded(
                child: Text(
                  filled ? value : (hint ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: filled ? AppText.body() : AppText.body(color: AppColors.textPlaceholder),
                ),
              ),
              if (onClear != null && enabled)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: Padding(
                    padding: EdgeInsets.only(left: 6.w),
                    child: Icon(PhosphorIconsRegular.x, size: 15.sp, color: AppColors.textMuted),
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 17.sp, color: AppColors.textMuted)
              else
                Icon(PhosphorIconsBold.caretDown, size: 14.sp, color: AppColors.textPlaceholder),
            ]),
          ),
        ),
      ),
      if (error != null)
        _errorText(error!)
      else if (helper != null)
        Padding(
          padding: EdgeInsets.only(top: 6.h, left: 2.w),
          child: Text(helper!, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ),
    ]);
  }
}
