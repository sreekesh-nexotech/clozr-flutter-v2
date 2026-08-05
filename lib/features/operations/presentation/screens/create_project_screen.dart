import 'package:flutter/material.dart';
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
import '../../application/providers/projects_providers.dart';
import '../components/ops_form_scaffold.dart';
import '../components/ops_widgets.dart';

/// New Project — full-screen create form with an Advanced section.
class CreateProjectScreen extends ConsumerStatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  ConsumerState<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends ConsumerState<CreateProjectScreen> {
  final _name = TextEditingController();
  final _cost = TextEditingController();
  final _desc = TextEditingController();

  String _customer = '';
  String _type = 'Fit-out';
  String _pri = 'Medium';
  DateTime? _start;
  DateTime? _end;
  String? _manager;
  final Set<String> _assignees = {};
  String _team = '';
  String _status = 'planning';
  String _visibility = 'Organization';
  String _method = 'Task Completion';
  bool _advanced = false;

  static const _types = ['Fit-out', 'Design Services', 'Joinery', 'MEP & Services', 'Furniture', 'AMC / Maintenance', 'Internal'];
  static const _vis = ['Organization', 'Team', 'Private'];
  static const _methods = ['Task Completion', 'Manual'];

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _endErr => _start != null && _end != null && _end!.isBefore(_start!);

  /// API mode: create remotely, refresh the list, toast + pop as before.
  /// Mock mode: exactly the previous local toast-and-pop behavior.
  Future<void> _submit() async {
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Project created');
      context.pop();
      return;
    }
    try {
      await ref.read(projectsRepositoryProvider).createProject({
        'project_name': _name.text.trim(),
        'priority': _pri,
        'description': _desc.text.trim(),
        if (_end != null) 'expected_end_date': _apiDate(_end!),
      });
      if (!mounted) return;
      ref.invalidate(projectsProvider);
      ref.read(toastProvider.notifier).show('Project created');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(e.message);
    }
  }

  /// API date format (`2026-08-30`).
  static String _apiDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsListProvider);
    final roster = ref.watch(rosterProvider);
    final customers = {for (final p in projects) if (p.company != null) p.company!}.toList();
    final teams = {for (final r in roster) if (r.team.isNotEmpty) r.team}.toList();
    final mgrName = _manager == null ? '' : MockUsers.of(_manager!).name;

    return OpsFormScaffold(
      title: 'New Project',
      ctaLabel: 'Create Project',
      ctaEnabled: _name.text.trim().isNotEmpty,
      onClose: () => context.pop(),
      onSubmit: _submit,
      children: [
        AppTextField(label: 'Project name', required: true, controller: _name, hint: 'e.g. Showroom fit-out', onChanged: (_) => setState(() {})),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Customer',
          value: _customer,
          placeholder: 'Internal project',
          caret: PhosphorIconsRegular.magnifyingGlass,
          onTap: () async {
            final v = await showOpsOptionPicker(
              context: context,
              title: 'Select customer',
              options: [(value: '', label: 'Internal project'), for (final c in customers) (value: c, label: c)],
              currentValue: _customer,
            );
            if (v != null) setState(() => _customer = v);
          },
        ),
        Padding(
          padding: EdgeInsets.only(top: 5.h),
          child: Text('Leave empty for internal projects.', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Project type',
          value: _type,
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Project type', options: [for (final t in _types) (value: t, label: t)], currentValue: _type);
            if (v != null) setState(() => _type = v);
          },
        ),
        SizedBox(height: 14.h),
        _label('Priority'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, children: [
          for (final p in const ['High', 'Medium', 'Low'])
            OpsFormChip(label: p, selected: _pri == p, onTap: () => setState(() => _pri = p)),
        ]),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(child: _dateField('Expected start', _start, (d) => setState(() => _start = d))),
            SizedBox(width: 9.w),
            Expanded(child: _dateField('Expected end', _end, (d) => setState(() => _end = d))),
          ],
        ),
        if (_endErr) ...[
          SizedBox(height: 8.h),
          Text('End must be on or after start.', style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.error)),
        ],
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Project manager',
          value: mgrName,
          placeholder: 'Select manager…',
          caret: PhosphorIconsBold.caretRight,
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Project manager', options: [for (final r in roster) (value: r.id, label: r.name)], currentValue: _manager ?? '');
            if (v != null) setState(() => _manager = v);
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
              onTap: () => setState(() => _assignees.contains(r.id) ? _assignees.remove(r.id) : _assignees.add(r.id)),
            ),
        ]),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Assigned team',
          value: _team,
          placeholder: 'Select team…',
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Assigned team', options: [(value: '', label: 'Select team…'), for (final t in teams) (value: t, label: t)], currentValue: _team);
            if (v != null) setState(() => _team = v);
          },
        ),
        SizedBox(height: 14.h),
        AppTextField(label: 'Description', controller: _desc, hint: 'Scope, goals, notes…', multiline: true),
        SizedBox(height: 6.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _advanced = !_advanced),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 13.h),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
            child: Row(
              children: [
                Expanded(child: Text('Advanced', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary))),
                Icon(_advanced ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 13.sp, color: AppColors.textMuted2),
              ],
            ),
          ),
        ),
        if (_advanced) ...[
          SizedBox(height: 6.h),
          _label('Status'),
          SizedBox(height: 7.h),
          Wrap(spacing: 8.w, runSpacing: 8.h, children: [
            for (final e in StatusMeta$.project.entries)
              OpsFormChip(label: e.value.label, selected: _status == e.key, onTap: () => setState(() => _status = e.key)),
          ]),
          SizedBox(height: 14.h),
          OpsPickerField(
            label: 'Visibility',
            value: _visibility,
            onTap: () async {
              final v = await showOpsOptionPicker(context: context, title: 'Visibility', options: [for (final o in _vis) (value: o, label: o)], currentValue: _visibility);
              if (v != null) setState(() => _visibility = v);
            },
          ),
          SizedBox(height: 14.h),
          OpsPickerField(
            label: 'Progress method',
            value: _method,
            onTap: () async {
              final v = await showOpsOptionPicker(context: context, title: 'Progress method', options: [for (final o in _methods) (value: o, label: o)], currentValue: _method);
              if (v != null) setState(() => _method = v);
            },
          ),
          SizedBox(height: 14.h),
          AppTextField(label: 'Estimated cost', controller: _cost, hint: 'e.g. 18L'),
        ],
      ],
    );
  }

  Widget _label(String t) => Text(t, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt));

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
