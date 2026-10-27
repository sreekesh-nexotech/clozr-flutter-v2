import 'package:flutter/material.dart';
import '../../../../core/filters/filter_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../../crm/application/providers/customers_providers.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../crm/domain/entities/customer.dart';
import '../../application/project_write_fields.dart';
import '../../application/providers/projects_providers.dart';
import '../../application/providers/project_form_providers.dart';
import '../components/project_close.dart';
import '../../../../core/network/network_providers.dart';
import '../components/ops_form_scaffold.dart';
import '../components/ops_widgets.dart';

/// Edit Project — prefilled form (Basics / Schedule / People / Tracking) with a
/// discard-confirm on close. Progress % is editable only when method = Manual.
class EditProjectScreen extends ConsumerStatefulWidget {
  const EditProjectScreen({super.key});

  @override
  ConsumerState<EditProjectScreen> createState() => _EditProjectScreenState();
}

class _EditProjectScreenState extends ConsumerState<EditProjectScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _cost = TextEditingController();
  final _progress = TextEditingController();

  bool _init = false;
  bool _dirty = false;
  /// The uuid — the write key, never shown.
  String _id = '';

  /// The human code the header shows. It printed [_id], so the user saw
  /// 36 characters of uuid where the record's own number belongs.
  String _code = '';
  String _customer = '';
  String _type = 'Fit-out';
  String _pri = 'Medium';
  DateTime? _start;
  DateTime? _end;
  String? _manager;
  final Set<String> _assignees = {};
  String _team = '';
  // The loaded team's name and id, to re-send it unchanged by id.
  String _origTeam = '';
  String _origTeamId = '';
  /// The org's own status name.
  String _status = '';
  String _visibility = 'Team';
  String _method = 'Task Completion';
  /// The linked quote's id (empty = none).
  String _quote = '';
  bool _saving = false;
  /// The record's `can_manage`: false locks the governed fields.
  bool _govLocked = false;
  String? _nameErr;
  String? _endErrMsg;
  // Manual progress outside 0–100 (webapp `ProgressMetric`).
  String? _progressErr;

  static const _vis = ['Private', 'Team', 'Organization'];
  // Webapp METHOD_OPTIONS — all four.
  static const _methods = ['Task Completion', 'Task Progress', 'Task Weight', 'Manual'];

  /// Webapp `projectGovernance.ts`.
  static const _govNote =
      "You can edit this project's details. Its status, dates, visibility, manager, assignees and team are changed by its owner, manager or an admin.";
  static const _govReason = 'Only the project owner, manager or an admin can change this.';

  /// Runs [open] unless the field is governed and locked, in which case it
  /// says why (the webapp shows the same text as a tooltip on the disabled field).
  void _governed(VoidCallback open) {
    if (_govLocked) {
      ref.read(toastProvider.notifier).show(_govReason);
      return;
    }
    open();
  }

  /// A governed field, dimmed while locked.
  Widget _gov(Widget child) => _govLocked ? Opacity(opacity: 0.55, child: child) : child;

  /// Manager / assignee choices: assignable users (webapp), plus anyone already
  /// on the record who has since lost access — re-saving them is allowed.
  List<({String id, String name, String initials})> _people(List<AppUser> roster) {
    final assignable = ref.read(projectAssignableUsersProvider).valueOrNull;
    final base = assignable == null
        ? [for (final r in roster) (id: r.id, name: r.name, initials: r.initials)]
        : [for (final u in assignable) (id: u.id, name: u.name, initials: MockUsers.of(u.id).initials)];
    final ids = {for (final b in base) b.id};
    return [
      ...base,
      for (final id in {if (_manager != null && _manager!.isNotEmpty) _manager!, ..._assignees})
        if (!ids.contains(id))
          (id: id, name: MockUsers.of(id).name, initials: MockUsers.of(id).initials),
    ];
  }

  String? get _customerId => _customerOptions
      .where((c) => c.name == _customer && _customer.isNotEmpty)
      .map((c) => c.id)
      .firstOrNull;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _cost.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _dirtied() {
    if (!_dirty) _dirty = true;
  }

  bool get _endErr => _start != null && _end != null && _end!.isBefore(_start!);
  bool get _isManual => _method == 'Manual';

  /// API mode: PATCH the edited fields, refresh the list, toast + pop as
  /// before. Mock mode: exactly the previous local toast-and-pop behavior.
  Future<void> _save({bool cancelOpenTasks = false, int? openCount}) async {
    if (_saving) return;
    final nameErr = _name.text.trim().isEmpty ? 'Project name is required' : null;
    final endErr = _endErr ? 'End date must be after the start date' : null;
    final pct = num.tryParse(_progress.text.trim());
    final progressErr = _isManual &&
            _progress.text.trim().isNotEmpty &&
            (pct == null || pct < 0 || pct > 100)
        ? 'Enter a number between 0 and 100.'
        : null;
    setState(() {
      _nameErr = nameErr;
      _endErrMsg = endErr;
      _progressErr = progressErr;
    });
    if (nameErr != null || endErr != null || progressErr != null) return;
    // A cost the parser cannot read must not be saved as whatever digits were
    // left in it — "20K" used to land as ₹20 with no warning.
    if (!isValidCostAmount(_cost.text)) {
      ref.read(toastProvider.notifier)
          .show('Enter the cost as a number, or a short form like 18L, 20K or 1.5Cr');
      return;
    }
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Changes saved');
      context.pop();
      return;
    }
    setState(() => _saving = true);
    try {
      // Everything the form collects. This sent four keys, so a changed
      // customer, project type, status, team, manager, assignee set, cost,
      // start date, visibility or progress method was accepted by the UI and
      // never reached the server.
      await ref.read(projectsRepositoryProvider).updateProject(
            _id,
            projectWriteFields(
              name: _name.text,
              priority: _pri,
              description: _desc.text,
              customerLabel: _customer,
              typeLabel: _type,
              statusLabel: _status,
              teamLabel: _team,
              managerId: _manager,
              assigneeIds: _assignees,
              cost: _cost.text,
              start: _start,
              end: _end,
              visibility: _visibility,
              progressMethod: _method,
              // Editable only when the method is Manual, which is also the only
              // case the API stores it in.
              percentComplete: _isManual ? _progress.text : null,
              // Always sent on edit: '' clears the link (webapp sends null).
              quotationId: _quote,
              customers: _customerOptions,
              types: ref.read(projectTypeOptionsProvider),
              statuses: ref.read(projectStatusOptionsProvider),
              teams: _teamOptions,
              teamFallbackId: _team == _origTeam ? _origTeamId : '',
            )..addAll(cancelOpenTasks ? openTasksActionCancel : const {}),
          );
      if (!mounted) return;
      // The list *and* the record behind the detail page — without the second
      // one the screen re-renders the pre-edit values it already had.
      ref.invalidate(projectsProvider);
      ref.invalidate(projectDetailProvider(_id));
      ref.read(toastProvider.notifier).show(
          cancelOpenTasks ? closedWithOpenTasksMessage(openCount) : 'Changes saved');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ref.read(apiServiceProvider).handled(e);
      // A close refused for open tasks is a question (webapp D24): confirm and
      // resend the same edit with `open_tasks_action: cancel`.
      final conflict = cancelOpenTasks ? null : openTasksConflict(e);
      if (conflict != null) {
        if (await confirmCloseWithOpenTasks(context, conflict.count) && mounted) {
          await _save(cancelOpenTasks: true, openCount: conflict.count);
        }
        return;
      }
      // Webapp `surfaceError`: a governance refusal names the fields — a toast;
      // a name problem on the name field, a date problem on the end date,
      // anything else a toast, in the server's words without `field:`.
      final msg = e.bareMessage;
      if (e.code == 'PROJECT_GOVERNANCE_FIELD') {
        ref.read(toastProvider.notifier).showError(msg);
      } else if (RegExp('name', caseSensitive: false).hasMatch(msg)) {
        setState(() => _nameErr = msg);
      } else if (RegExp('end date|start date', caseSensitive: false).hasMatch(msg)) {
        setState(() => _endErrMsg = msg);
      } else {
        ref.read(toastProvider.notifier).showError(msg);
      }
    }
  }


  /// The org's customers and teams as catalog options, so a picked label can be
  /// resolved back to the UUID the API wants.
  List<CatalogOption> get _customerOptions => [
        for (final c in ref.read(customersProvider).valueOrNull ?? const <Customer>[])
          CatalogOption(id: c.id, name: c.company?.trim().isNotEmpty == true ? c.company! : c.name),
      ];


  /// The org's own project types (`/projects/project-types/`).
  ///
  /// No built-in fallback: only a name that matches a catalog entry resolves to
  /// the `project_type_id` the API takes, so offering the prototype's seven
  /// invented types meant picking one and having it silently dropped from the
  /// write. An org with no types configured has nothing to choose here.
  List<String> get _typeNames =>
      [for (final t in ref.read(projectTypeOptionsProvider)) t.name];

  List<CatalogOption> get _teamOptions => [
        ...?ref.read(projectTeamsProvider).valueOrNull,
      ];


  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    // The enriched record, so the form opens on the project's real customer,
    // type, team, cost, visibility and progress method rather than the list
    // row's blanks and old placeholders.
    final project = ref.watch(projectDetailOrListProvider(id));

    if (project == null) {
      return OpsEditScaffold(
        title: 'Edit project',
        subtitle: '—',
        onClose: () => context.pop(),
        onSave: () => context.pop(),
        children: const [Center(child: Text('Project not found'))],
      );
    }

    if (!_init) {
      _init = true;
      _id = project.id;
    _code = project.code;
      _name.text = project.name;
      _desc.text = project.desc;
      // The raw amount, not the display string: "₹25L" stripped to its digits
      // is 25, so prefilling from `cost` turned ₹25 lakh into ₹25 on save.
      _cost.text = project.costNum > 0
          ? project.costNum.toStringAsFixed(0)
          : '';
      _progress.text = '${project.progress}';
      _customer = project.internal ? '' : (project.company ?? '');
      _type = project.type;
      _pri = project.pri;
      _start = opsParseDisplayDate(project.start);
      _end = opsParseDisplayDate(project.end);
      _manager = project.manager;
      _assignees.addAll(project.assignees);
      _status = project.statusName.isNotEmpty
          ? project.statusName
          : (StatusMeta$.project[project.status]?.label ?? '');
      _team = project.team;
      _origTeam = project.team;
      _origTeamId = project.teamId;
      _quote = project.quotationId;
      // Empty until the detail record lands; keep the form's defaults rather
      // than showing a value the project does not have.
      if (project.visibility.isNotEmpty) _visibility = project.visibility;
      if (project.method.isNotEmpty) _method = project.method;
    }
    // Follows the record: the detail fetch may land after the first build.
    _govLocked = project.canManage == false;
    if (_quote.isEmpty && project.quotationId.isNotEmpty && !_dirty) _quote = project.quotationId;

    // Watched here, not read inside the pickers' onTap: the type and status
    // catalogs are what a picked label resolves to an id against, and until
    // now nothing fetched them unless the user happened to open a picker —
    // so `/projects/project-types/` was never called and every saved
    // project_type was quietly dropped.
    ref.watch(projectTypeCatalogProvider);
    ref.watch(projectStatusCatalogProvider);
    ref.watch(customersProvider);
    ref.watch(projectTeamsProvider);
    ref.watch(projectAssignableUsersProvider);
    final roster = ref.watch(rosterProvider);
    final people = _people(roster);
    final statusNames = [for (final st in ref.watch(projectStatusOptionsProvider)) st.name];
    final custId = _customerId;
    final quotes = custId == null
        ? const <CatalogOption>[]
        : ref.watch(customerQuotesProvider(custId)).valueOrNull ?? const <CatalogOption>[];
    // The org's real customers — see the create screen for why.
    final customers = [for (final c in _customerOptions) c.name];
    // The org's real teams, so the picked label resolves to a `team_id`.
    // This listed the team names sitting on roster users.
    final teams = [for (final t in _teamOptions) t.name];
    // No manager → the placeholder, not "Unknown".
    final mgr = (_manager ?? '').isEmpty ? null : MockUsers.of(_manager!);

    return OpsEditScaffold(
      title: 'Edit project',
      subtitle: _code.isEmpty
          // `task_code` is null for a standalone task, and an empty code
          // would leave a dangling separator.
          ? 'Changes apply on save'
          : '$_code · changes apply on save',
      onClose: () => handleEditClose(context, dirty: _dirty),
      onSave: _save,
      children: [
        if (_govLocked) ...[
          Container(
            padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 11.h),
            decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(12.r)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PhosphorIconsFill.info, size: 16.sp, color: AppColors.textMuted2),
                SizedBox(width: 9.w),
                Expanded(child: Text(_govNote, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.45))),
              ],
            ),
          ),
          SizedBox(height: 10.h),
        ],
        const OpsSectionLabel('Basics', first: true),
        AppTextField(label: 'Project name', required: true, controller: _name, hint: 'e.g. Showroom fit-out', errorText: _nameErr, onChanged: (_) => setState(() { _nameErr = null; _dirtied(); })),
        SizedBox(height: 14.h),
        AppTextField(label: 'Description', controller: _desc, hint: 'What is this project delivering?', multiline: true, onChanged: (_) => _dirtied()),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Customer',
          value: _customer,
          placeholder: 'Internal project',
          caret: PhosphorIconsBold.caretRight,
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Select customer', options: [(value: '', label: 'Internal project'), for (final c in customers) (value: c, label: c)], currentValue: _customer);
            // A quote belongs to one customer: changing it clears the link.
            if (v != null) setState(() { if (v != _customer) _quote = ''; _customer = v; _dirtied(); });
          },
        ),
        if (custId != null) ...[
          SizedBox(height: 14.h),
          OpsPickerField(
            label: 'Linked quote',
            value: quotes.where((q) => q.id == _quote).map((q) => q.name).firstOrNull ?? '',
            placeholder: 'No linked quote',
            onTap: () async {
              final v = await showOpsOptionPicker(
                context: context,
                title: 'Linked quote',
                options: [(value: '', label: 'No linked quote'), for (final q in quotes) (value: q.id, label: q.name)],
                currentValue: _quote,
              );
              if (v != null) setState(() { _quote = v; _dirtied(); });
            },
          ),
          Padding(
            padding: EdgeInsets.only(top: 5.h),
            child: Text('Optional — the quote this project was won from. Accounting derives project financials from it.',
                style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          ),
        ],
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Project type',
          value: _type,
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Project type', options: [for (final t in _typeNames) (value: t, label: t)], currentValue: _type);
            if (v != null) setState(() { _type = v; _dirtied(); });
          },
        ),
        SizedBox(height: 14.h),
        _label('Priority'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final p in const ['High', 'Medium', 'Low'])
            OpsFormChip(label: p, selected: _pri == p, tone: StatusMeta$.projectPriority[p], onTap: () => setState(() { _pri = p; _dirtied(); })),
        ]),
        const OpsSectionLabel('Schedule'),
        Row(
          children: [
            Expanded(child: _gov(_dateField('Expected start', _start, (d) => setState(() { _start = d; _dirtied(); })))),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _gov(_dateField('Expected end', _end, (d) => setState(() { _end = d; _endErrMsg = null; _dirtied(); }))),
                  if (_endErrMsg != null || _endErr)
                    Padding(
                      padding: EdgeInsets.only(top: 6.h),
                      child: Text(_endErrMsg ?? 'End date must be after the start date', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.error)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const OpsSectionLabel('People'),
        _gov(OpsPickerField(
          label: 'Project manager',
          value: mgr?.name ?? '',
          placeholder: 'Select manager…',
          caret: PhosphorIconsBold.caretRight,
          onTap: () => _governed(() async {
            final v = await showOpsOptionPicker(context: context, title: 'Project manager', options: [for (final r in people) (value: r.id, label: r.name)], currentValue: _manager ?? '');
            if (v != null) setState(() { _manager = v; _dirtied(); });
          }),
        )),
        SizedBox(height: 14.h),
        _label('Assignees'),
        SizedBox(height: 7.h),
        _gov(Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final r in people)
            OpsAssigneeChip(
              initials: r.initials,
              name: r.name.split(' ').first,
              color: MockUsers.memberColors[r.id] ?? AppColors.navy,
              selected: _assignees.contains(r.id),
              filled: false,
              onTap: () => _governed(() => setState(() { _assignees.contains(r.id) ? _assignees.remove(r.id) : _assignees.add(r.id); _dirtied(); })),
            ),
        ])),
        SizedBox(height: 14.h),
        _gov(OpsPickerField(
          label: 'Assigned team',
          value: _team,
          placeholder: 'No team',
          onTap: () => _governed(() async {
            final v = await showOpsOptionPicker(context: context, title: 'Assigned team', options: [(value: '', label: 'No team'), for (final t in teams) (value: t, label: t)], currentValue: _team);
            if (v != null) setState(() { _team = v; _dirtied(); });
          }),
        )),
        const OpsSectionLabel('Tracking'),
        _label('Status'),
        SizedBox(height: 7.h),
        // The org's own statuses, with their own colours.
        _gov(Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          if (statusNames.isEmpty)
            for (final e in StatusMeta$.project.entries)
              OpsFormChip(label: e.value.label, selected: _status.toLowerCase() == e.value.label.toLowerCase(), tone: e.value.color, onTap: () => _governed(() => setState(() { _status = e.value.label; _dirtied(); })))
          else
            for (final st in ref.watch(projectStatusOptionsProvider))
              OpsFormChip(label: st.name, selected: _status.toLowerCase() == st.name.toLowerCase(), tone: st.color, onTap: () => _governed(() => setState(() { _status = st.name; _dirtied(); }))),
        ])),
        SizedBox(height: 14.h),
        _gov(OpsPickerField(
          label: 'Visibility',
          value: _visibility,
          onTap: () => _governed(() async {
            final v = await showOpsOptionPicker(context: context, title: 'Visibility', options: [for (final o in _vis) (value: o, label: o)], currentValue: _visibility);
            if (v != null) setState(() { _visibility = v; _dirtied(); });
          }),
        )),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Progress method',
          value: _method,
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Progress method', options: [for (final o in _methods) (value: o, label: o)], currentValue: _method);
            if (v != null) setState(() { _method = v; _dirtied(); });
          },
        ),
        SizedBox(height: 14.h),
        if (_isManual)
          AppTextField(label: 'Progress (%)', controller: _progress, keyboardType: TextInputType.number, errorText: _progressErr, onChanged: (_) => setState(() { _progressErr = null; _dirtied(); }))
        else
          _calculatedProgress(),
        SizedBox(height: 14.h),
        AppTextField(label: 'Estimated cost', controller: _cost, hint: 'e.g. 48L, 20K or 4800000', onChanged: (_) => _dirtied()),
      ],
    );
  }

  Widget _label(String t) => Text(t, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt));

  Widget _calculatedProgress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Progress'),
        SizedBox(height: 7.h),
        Container(
          height: 46.h,
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          decoration: BoxDecoration(color: const Color(0xFFEFF0F2), borderRadius: BorderRadius.circular(11.r)),
          child: Row(
            children: [
              Text('${_progress.text}%', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
              const Spacer(),
              Text('Calculated from tasks', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick) {
    return OpsPickerField(
      label: label,
      value: value == null ? '' : opsFmtDate(value),
      placeholder: 'Pick a date',
      caret: PhosphorIconsRegular.calendarBlank,
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: value ?? kFilterToday, firstDate: DateTime(2024), lastDate: DateTime(2030));
        if (d != null) onPick(d);
      },
    );
  }
}
