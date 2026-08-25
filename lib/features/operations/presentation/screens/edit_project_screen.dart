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
import '../../../people/application/providers/people_providers.dart';
import '../../../people/domain/entities/team.dart';
import '../../application/project_write_fields.dart';
import '../../application/providers/projects_providers.dart';
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
  String _status = 'planning';
  String _visibility = 'Team';
  String _method = 'Task Completion';

  static const _vis = ['Organization', 'Team', 'Private'];
  static const _methods = ['Task Completion', 'Manual'];

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
  Future<void> _save() async {
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Changes saved');
      context.pop();
      return;
    }
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
              statusLabel: _statusLabel,
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
              customers: _customerOptions,
              types: ref.read(projectTypeOptionsProvider),
              statuses: ref.read(projectStatusOptionsProvider),
              teams: _teamOptions,
            ),
          );
      if (!mounted) return;
      // The list *and* the record behind the detail page — without the second
      // one the screen re-renders the pre-edit values it already had.
      ref.invalidate(projectsProvider);
      ref.invalidate(projectDetailProvider(_id));
      ref.read(toastProvider.notifier).show('Changes saved');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).showError(e.message);
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
        for (final t in ref.read(teamsProvider).valueOrNull ?? const <Team>[])
          CatalogOption(id: t.id, name: t.name),
      ];

  /// The picker holds a folded key ("planning"); the API wants the org's own
  /// status row, matched by name.
  String get _statusLabel =>
      (StatusMeta$.project[_status] ?? StatusMeta$.project['planning']!).label;

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
      _status = project.status;
      _team = project.team;
      // Empty until the detail record lands; keep the form's defaults rather
      // than showing a value the project does not have.
      if (project.visibility.isNotEmpty) _visibility = project.visibility;
      if (project.method.isNotEmpty) _method = project.method;
    }

    // Watched here, not read inside the pickers' onTap: the type and status
    // catalogs are what a picked label resolves to an id against, and until
    // now nothing fetched them unless the user happened to open a picker —
    // so `/projects/project-types/` was never called and every saved
    // project_type was quietly dropped.
    ref.watch(projectTypeCatalogProvider);
    ref.watch(projectStatusCatalogProvider);
    ref.watch(customersProvider);
    ref.watch(teamsProvider);
    final roster = ref.watch(rosterProvider);
    // The org's real customers — see the create screen for why.
    final customers = [for (final c in _customerOptions) c.name];
    // The org's real teams, so the picked label resolves to a `team_id`.
    // This listed the team names sitting on roster users.
    final teams = [for (final t in _teamOptions) t.name];
    final mgr = _manager == null ? null : MockUsers.of(_manager!);

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
        const OpsSectionLabel('Basics', first: true),
        AppTextField(label: 'Project name', required: true, controller: _name, hint: 'e.g. Showroom fit-out', onChanged: (_) => setState(_dirtied)),
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
            if (v != null) setState(() { _customer = v; _dirtied(); });
          },
        ),
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
            Expanded(child: _dateField('Expected start', _start, (d) => setState(() { _start = d; _dirtied(); }))),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dateField('Expected end', _end, (d) => setState(() { _end = d; _dirtied(); })),
                  if (_endErr)
                    Padding(
                      padding: EdgeInsets.only(top: 6.h),
                      child: Text('Ends before it starts', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.error)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const OpsSectionLabel('People'),
        OpsPickerField(
          label: 'Project manager',
          value: mgr?.name ?? '',
          placeholder: 'Select manager…',
          caret: PhosphorIconsBold.caretRight,
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Project manager', options: [for (final r in roster) (value: r.id, label: r.name)], currentValue: _manager ?? '');
            if (v != null) setState(() { _manager = v; _dirtied(); });
          },
        ),
        SizedBox(height: 14.h),
        _label('Assignees'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final r in roster)
            OpsAssigneeChip(
              initials: r.initials,
              name: r.firstName,
              color: MockUsers.memberColors[r.id] ?? AppColors.navy,
              selected: _assignees.contains(r.id),
              filled: false,
              onTap: () => setState(() { _assignees.contains(r.id) ? _assignees.remove(r.id) : _assignees.add(r.id); _dirtied(); }),
            ),
        ]),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Assigned team',
          value: _team,
          placeholder: 'No team',
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Assigned team', options: [(value: '', label: 'No team'), for (final t in teams) (value: t, label: t)], currentValue: _team);
            if (v != null) setState(() { _team = v; _dirtied(); });
          },
        ),
        const OpsSectionLabel('Tracking'),
        _label('Status'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final e in StatusMeta$.project.entries)
            OpsFormChip(label: e.value.label, selected: _status == e.key, tone: e.value.color, onTap: () => setState(() { _status = e.key; _dirtied(); })),
        ]),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Visibility',
          value: _visibility,
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Visibility', options: [for (final o in _vis) (value: o, label: o)], currentValue: _visibility);
            if (v != null) setState(() { _visibility = v; _dirtied(); });
          },
        ),
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
          AppTextField(label: 'Progress (%)', controller: _progress, keyboardType: TextInputType.number, onChanged: (_) => _dirtied())
        else
          _calculatedProgress(),
        SizedBox(height: 14.h),
        AppTextField(label: 'Estimated cost', controller: _cost, hint: 'e.g. ₹48L', onChanged: (_) => _dirtied()),
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
