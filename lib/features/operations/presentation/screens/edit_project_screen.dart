import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
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
  String _id = '';
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

  static const _types = ['Fit-out', 'Design Services', 'Joinery', 'MEP & Services', 'Furniture', 'AMC / Maintenance', 'Internal'];
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

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final project = ref.watch(projectByIdProvider(id));

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
      _name.text = project.name;
      _desc.text = project.desc;
      _cost.text = project.cost;
      _progress.text = '${project.progress}';
      _customer = project.internal ? '' : (project.company ?? '');
      _type = project.type;
      _pri = project.pri;
      _start = opsParseDisplayDate(project.start);
      _end = opsParseDisplayDate(project.end);
      _manager = project.manager;
      _assignees.addAll(project.assignees);
      _status = project.status;
      _visibility = project.visibility;
      _method = project.method == 'Manual' ? 'Manual' : 'Task Completion';
    }

    final customers = {for (final p in ref.watch(projectsListProvider)) if (p.company != null) p.company!}.toList();
    final teams = {for (final r in MockUsers.reps) if (r.team.isNotEmpty) r.team}.toList();
    final mgr = _manager == null ? null : MockUsers.of(_manager!);

    return OpsEditScaffold(
      title: 'Edit project',
      subtitle: '$_id · changes apply on save',
      onClose: () => handleEditClose(context, dirty: _dirty),
      onSave: () {
        ref.read(toastProvider.notifier).show('Changes saved');
        context.pop();
      },
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
            final v = await showOpsOptionPicker(context: context, title: 'Project type', options: [for (final t in _types) (value: t, label: t)], currentValue: _type);
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
            final v = await showOpsOptionPicker(context: context, title: 'Project manager', options: [for (final r in MockUsers.reps) (value: r.id, label: r.name)], currentValue: _manager ?? '');
            if (v != null) setState(() { _manager = v; _dirtied(); });
          },
        ),
        SizedBox(height: 14.h),
        _label('Assignees'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final r in MockUsers.reps)
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
        final d = await showDatePicker(context: context, initialDate: value ?? DateTime(2026, 7, 9), firstDate: DateTime(2024), lastDate: DateTime(2030));
        if (d != null) onPick(d);
      },
    );
  }
}
