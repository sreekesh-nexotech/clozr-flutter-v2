import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/people_providers.dart';

/// Roles a new member can be invited as (prototype `roleOpts`).
const _roleOpts = <String>[
  'System Admin',
  'Executive Leadership',
  'Manager',
  'Sales executive',
  'Viewer',
];

/// Managers a member can report to (prototype `managerOpts`).
const _managerOpts = <String>['Manoj Varma', 'Lakshmi Pillai', 'Arjun Nair'];

/// Visibility scope implied by each role (prototype `inviteScopeHint` / SCOPES).
const _scopeByRole = <String, String>{
  'System Admin': 'Organization-wide',
  'Executive Leadership': 'Organization-wide',
  'Manager': 'Team-based + Reporting Hierarchy',
  'Sales executive': 'Self + Reporting Hierarchy',
  'Viewer': 'Organization-wide',
};

/// Opens the Invite member sheet — a faithful port of the prototype's
/// `inviteMember` sheet. Used by both the Members screen create button and the
/// contextual `+`.
Future<void> showInviteMemberSheet(BuildContext context) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => const _InviteMemberSheet(),
  );
}

class _InviteMemberSheet extends ConsumerStatefulWidget {
  const _InviteMemberSheet();

  @override
  ConsumerState<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends ConsumerState<_InviteMemberSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'Sales executive';
  String _manager = 'Arjun Nair';
  String _team = '—';
  bool _showErrors = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;
  bool get _emailOk => _email.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (!_nameOk || !_emailOk) {
      ref.read(toastProvider.notifier).show('Name and email are required');
      return;
    }
    final email = _email.text.trim();
    if (!ApiConfig.apiEnabled) {
      Navigator.of(context).pop();
      ref.read(toastProvider.notifier).show('Invite sent to $email');
      return;
    }

    // Resolve the picked role name against the loaded org roles (best-effort;
    // the invite is valid without a role).
    String? roleId;
    final roles = ref.read(rolesProvider).valueOrNull ?? const [];
    for (final r in roles) {
      if (r.name.toLowerCase() == _role.toLowerCase()) {
        roleId = r.id;
        break;
      }
    }
    final phone = _phone.text.trim();
    try {
      await ref.read(peopleRepositoryProvider).inviteMember(
            email: email,
            name: _name.text.trim(),
            phone: phone.isEmpty ? null : phone,
            roleId: roleId,
          );
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(e.message);
      return;
    }
    if (!mounted) return;
    ref.invalidate(membersProvider);
    Navigator.of(context).pop();
    ref.read(toastProvider.notifier).show('Invite sent to $email');
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(teamsProvider).valueOrNull ?? const [];
    final teamOpts = <(String, String)>[
      ('—', 'No team'),
      for (final t in teams) (t.name, t.name),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Invite member', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 18.h),
            children: [
              AppTextField(
                label: 'Full name',
                required: true,
                controller: _name,
                hint: 'e.g. Anjali Rao',
                errorText: _showErrors && !_nameOk ? 'Enter a full name' : null,
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 14.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Email',
                      required: true,
                      controller: _email,
                      hint: 'name@kairali.in',
                      keyboardType: TextInputType.emailAddress,
                      errorText: _showErrors && !_emailOk ? 'Enter an email' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: AppTextField(
                      label: 'Phone',
                      controller: _phone,
                      hint: '+91 …',
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Role',
                readOnly: true,
                value: _role,
                onTap: () => _pickOne(
                  title: 'Role',
                  options: [for (final r in _roleOpts) (r, r)],
                  current: _role,
                  onPick: (v) => setState(() => _role = v),
                ),
              ),
              SizedBox(height: 6.h),
              _hint(PhosphorIconsRegular.eye, 'Scope: ${_scopeByRole[_role] ?? '—'}'),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Reporting manager',
                required: true,
                readOnly: true,
                value: _manager,
                onTap: () => _pickOne(
                  title: 'Reporting manager',
                  options: [for (final m in _managerOpts) (m, m)],
                  current: _manager,
                  onPick: (v) => setState(() => _manager = v),
                ),
              ),
              SizedBox(height: 6.h),
              _hint(null, 'Reports to a manager or executive — never directly to the System Admin.'),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Team',
                readOnly: true,
                value: _team == '—' ? 'No team' : _team,
                onTap: () => _pickOne(
                  title: 'Team',
                  options: teamOpts,
                  current: _team,
                  onPick: (v) => setState(() => _team = v),
                ),
              ),
              SizedBox(height: 20.h),
              PrimaryButton(
                label: 'Send invite',
                icon: PhosphorIconsRegular.paperPlaneTilt,
                height: 48,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hint(IconData? icon, String text) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12.sp, color: AppColors.textPlaceholder),
          SizedBox(width: 5.w),
        ],
        Expanded(
          child: Text(text,
              style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ),
      ],
    );
  }

  void _pickOne({
    required String title,
    required List<(String, String)> options,
    required String current,
    required ValueChanged<String> onPick,
  }) {
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: title, onClose: () => Navigator.of(ctx).pop()),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
              children: [
                for (final (value, label) in options)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      onPick(value);
                      Navigator.of(ctx).pop();
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 11.h, horizontal: 6.w),
                      child: Row(
                        children: [
                          Expanded(child: Text(label, style: AppText.body())),
                          if (value == current)
                            Icon(PhosphorIconsBold.check, size: 19.sp, color: AppColors.success),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
