import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/phone_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/people_providers.dart';

/// The role vocabulary used until the org's own arrives — the prototype's five.
///
/// A fallback only. The pickers prefer `GET /management/roles/` and
/// `GET /management/users/` (`members.md` Part 1), which is also where the
/// ids the create body needs come from: a name picked off a hardcoded list has
/// no `role_id` to send.
const _fallbackRoleNames = <String>[
  'System Admin',
  'Executive Leadership',
  'Manager',
  'Sales executive',
  'Viewer',
];

/// Visibility scope per built-in role, for the hint under the Role picker.
/// Superseded by the role's own `scope` once the catalog loads.
const _fallbackScopeByRole = <String, String>{
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

  /// The chosen manager's `user_id` — what the create body sends. Empty means
  /// "no reporting manager", which the API accepts.
  String _managerId = '';
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

  /// Phone is optional — blank is fine. A half-typed number is not: it would
  /// be stored as something nobody can dial.
  bool get _phoneOk =>
      PhoneFormat.isBlank(_phone.text) || PhoneFormat.isComplete(_phone.text);

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (!_nameOk || !_emailOk) {
      ref.read(toastProvider.notifier).show('Name and email are required');
      return;
    }
    if (!_phoneOk) {
      ref.read(toastProvider.notifier).show('Enter a 10-digit phone number');
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
    try {
      await ref.read(peopleRepositoryProvider).inviteMember(
            email: email,
            name: _name.text.trim(),
            // `+91XXXXXXXXXX`, matching how the backend stores numbers; null
            // when the field is empty.
            phone: PhoneFormat.forApi(_phone.text),
            roleId: roleId,
            // `manager_id` sets the reporting manager and its hierarchy row
            // (§Invite member). The picked manager was being collected and then
            // dropped — the invite always landed with no manager.
            managerId: _managerId.isEmpty ? null : _managerId,
          );
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).showError(e.message);
      return;
    }
    if (!mounted) return;
    ref.invalidate(membersProvider);
    Navigator.of(context).pop();
    final toast = ref.read(toastProvider.notifier);
    toast.show('Invite sent to $email');
    // The create body has no team field (§Invite member), and team membership
    // is a separate API. Saying so beats letting the picked team disappear.
    if (_team != '—') {
      toast.show('Add them to $_team from the team’s own page — '
          'inviting cannot assign a team yet');
    }
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(teamsProvider).valueOrNull ?? const [];
    final teamOpts = <(String, String)>[
      ('—', 'No team'),
      for (final t in teams) (t.name, t.name),
    ];

    // The org's own roles; the built-in five only until they load.
    final roles = ref.watch(rolesProvider).valueOrNull ?? const [];
    final roleOpts = roles.isEmpty
        ? [for (final r in _fallbackRoleNames) (r, r)]
        : [for (final r in roles) (r.name, r.name)];
    // The scope shown under the picker is the role's own once the catalog is
    // in — the built-in map cannot describe a role an admin created.
    final pickedRole = roles.where((r) => r.name == _role);
    final scopeHint = pickedRole.isNotEmpty && pickedRole.first.scope.isNotEmpty
        ? pickedRole.first.scope
        : (_fallbackScopeByRole[_role] ?? '—');

    // Any org user can be a manager (Part 1, "Any manager"), keyed by user_id
    // because that is what `manager_id` takes. This was three seed names —
    // "Manoj Varma", "Lakshmi Pillai", "Arjun Nair" — none of whom exist here.
    final members = ref.watch(membersProvider).valueOrNull ?? const [];
    final managerOpts = <(String, String)>[
      ('', 'No manager'),
      for (final m in members) (m.id, m.name),
    ];
    final managerLabel = _managerId.isEmpty
        ? 'No manager'
        : members
            .where((m) => m.id == _managerId)
            .map((m) => m.name)
            .firstOrNull ??
            'No manager';

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
                      // `+91` is a prefix, not text — it cannot be typed over,
                      // duplicated, or lost when the field is cleared.
                      prefix: PhoneFormat.dialCode,
                      hint: '98470 11001',
                      keyboardType: TextInputType.phone,
                      inputFormatters: PhoneFormat.inputFormatters,
                      errorText: _showErrors && !_phoneOk
                          ? 'Enter 10 digits'
                          : null,
                      onChanged: (_) => setState(() {}),
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
                  options: roleOpts,
                  current: _role,
                  onPick: (v) => setState(() => _role = v),
                ),
              ),
              SizedBox(height: 6.h),
              _hint(PhosphorIconsRegular.eye, 'Scope: $scopeHint'),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Reporting manager',
                readOnly: true,
                value: managerLabel,
                onTap: () => _pickOne(
                  title: 'Reporting manager',
                  options: managerOpts,
                  current: _managerId,
                  onPick: (v) => setState(() => _managerId = v),
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
