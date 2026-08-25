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
  // Starts unset, not on a guessed name. The picker offers only the org's own
  // `/projects/project-types/` rows now, so a hardcoded default like 'Fit-out'
  // matched no catalog entry: the form showed a type the payload then dropped.
  String _type = '';
  String _pri = 'Medium';
  DateTime? _start;
  DateTime? _end;
  String? _manager;
  final Set<String> _assignees = {};
  String _team = '';
  bool _saving = false;
  String _status = 'planning';
  String _visibility = 'Organization';
  String _method = 'Task Completion';
  bool _advanced = false;

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

  /// The org's customers and teams as catalog options, so the picked label can
  /// be resolved back to the UUID the API wants.
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

  /// The status picker holds a folded key ("planning"); the API wants the org's
  /// own status row, matched by name.
  String get _statusLabel =>
      (StatusMeta$.project[_status] ?? StatusMeta$.project['planning']!).label;

  /// API mode: create remotely, refresh the list, toast + pop as before.
  /// Mock mode: exactly the previous local toast-and-pop behavior.
  Future<void> _submit() async {
    // Without this a second tap during the round trip makes a second project —
    // the same duplicate-create already seen on tasks, customers and upsells.
    if (_saving) return;
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Project created');
      context.pop();
      return;
    }
    setState(() => _saving = true);
    try {
      // Everything the form collects, under the API's own keys. This used to
      // send four fields, so the manager, customer, type, team, assignees,
      // cost, start date, visibility and progress method were all gathered
      // from the user and dropped on the floor.
      await ref.read(projectsRepositoryProvider).createProject(
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
              customers: _customerOptions,
              types: ref.read(projectTypeOptionsProvider),
              statuses: ref.read(projectStatusOptionsProvider),
              teams: _teamOptions,
            ),
          );
      if (!mounted) return;
      // The whole family: the list renders from `projectsScopedProvider` under
      // whatever filter query is active, so dropping only the unfiltered
      // `projectsProvider` would leave the new project invisible.
      ref.invalidate(projectsScopedProvider);
      // The ops dashboard and the detail screen's fallback read the unfiltered
      // provider, so it has to drop too or they keep serving the stale list.
      ref.invalidate(projectsProvider);
      ref.read(toastProvider.notifier).show('Project created');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      // Back to enabled: the form still holds everything the user typed, and a
      // rejected name or date is meant to be fixed and resubmitted.
      setState(() => _saving = false);
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
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
    // The org's real customers, so the picked label resolves to the
    // `customer_id` the API wants. This listed the company names already on
    // loaded projects, so a customer never used on one could not be picked —
    // and the label matched no catalog entry.
    final customers = [for (final c in _customerOptions) c.name];
    // The org's real teams, so the picked label resolves to a `team_id`.
    // This listed the team names sitting on roster users.
    final teams = [for (final t in _teamOptions) t.name];
    final mgrName = _manager == null ? '' : MockUsers.of(_manager!).name;

    return OpsFormScaffold(
      title: 'New Project',
      ctaLabel: 'Create Project',
      // `&& !_saving` greys the CTA out for the round trip using the scaffold's
      // existing disabled styling — no spinner, no layout change.
      // `!_endErr` too: the end-date field already flags "before start", but the
      // CTA stayed live, so the form happily posted a range the API rejects.
      ctaEnabled: _name.text.trim().isNotEmpty && !_saving && !_endErr,
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
            final v = await showOpsOptionPicker(context: context, title: 'Project type', options: [for (final t in _typeNames) (value: t, label: t)], currentValue: _type);
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
        final d = await showDatePicker(context: context, initialDate: value ?? kFilterToday, firstDate: DateTime(2024), lastDate: DateTime(2030));
        if (d != null) onPick(d);
      },
    );
  }
}
