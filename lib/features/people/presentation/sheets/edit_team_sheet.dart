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
import '../../domain/entities/member.dart';
import '../../domain/entities/team.dart';

/// Opens the Edit team sheet — the create sheet's fields, prefilled from [team]
/// and saved with `PATCH /management/teams/{id}/` (`team-api.md` §1.5).
Future<void> showEditTeamSheet(BuildContext context, Team team) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _EditTeamSheet(team: team),
  );
}

class _EditTeamSheet extends ConsumerStatefulWidget {
  const _EditTeamSheet({required this.team});

  final Team team;

  @override
  ConsumerState<_EditTeamSheet> createState() => _EditTeamSheetState();
}

class _EditTeamSheetState extends ConsumerState<_EditTeamSheet> {
  late final TextEditingController _name;
  late final TextEditingController _zone;
  late String _lead;
  late List<String> _members;

  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.team.name);
    _zone = TextEditingController(text: widget.team.zone);
    _lead = widget.team.lead;
    _members = [...widget.team.members];
  }

  @override
  void dispose() {
    _name.dispose();
    _zone.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;

  /// Only what changed. A PATCH of the untouched roster would still be a full
  /// replacement server-side, and the team name is unique per org — resending an
  /// unchanged name is a needless chance of a 400 from a race.
  Map<String, dynamic> _changedFields() {
    final team = widget.team;
    final name = _name.text.trim();
    final zone = _zone.text.trim();
    final roster = {..._members, if (_lead.isNotEmpty) _lead}.toList();

    return {
      if (name != team.name) 'name': name,
      if (zone != team.zone) 'description': zone,
      // Empty clears the manager, so it is sent as an explicit null rather than
      // omitted — omitting it is how "leave the lead alone" is expressed.
      if (_lead != team.lead) 'manager_id': _lead.isEmpty ? null : _lead,
      if (!_sameRoster(roster, team.members)) 'member_ids': roster,
    };
  }

  static bool _sameRoster(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _showErrors = true);
    if (!_nameOk) {
      ref.read(toastProvider.notifier).show('Enter a team name');
      return;
    }
    final name = _name.text.trim();
    final fields = _changedFields();
    if (fields.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (!ApiConfig.apiEnabled) {
      Navigator.of(context).pop();
      ref.read(toastProvider.notifier).show('Team "$name" updated');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(peopleRepositoryProvider).updateTeam(widget.team.id, fields);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ref.read(toastProvider.notifier).showError(e.message);
      return;
    }
    if (!mounted) return;
    // One invalidate covers the roster too: `getTeams()` groups the flat
    // org-wide TeamMember list, so the counts and avatar stack refresh with it.
    ref.invalidate(teamsProvider);
    Navigator.of(context).pop();
    ref.read(toastProvider.notifier).show('Team "$name" updated');
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider).valueOrNull ?? const [];
    final byId = ref.watch(membersByIdProvider);
    final leadOpts = <(String, String)>[
      ('', 'No lead'),
      for (final m in members) (m.id, m.name),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Edit team', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 18.h),
            children: [
              AppTextField(
                label: 'Team name',
                required: true,
                controller: _name,
                hint: 'e.g. Team East',
                errorText: _showErrors && !_nameOk ? 'Enter a team name' : null,
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Region / function (optional)',
                controller: _zone,
                hint: 'e.g. East zone',
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Team lead (optional)',
                readOnly: true,
                value: _lead.isEmpty ? 'No lead' : (byId[_lead]?.name ?? _lead),
                onTap: () => _pickLead(leadOpts),
              ),
              SizedBox(height: 6.h),
              Text(
                'Team lead is a designation only — it grants no scope or permissions.',
                style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder),
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Members',
                readOnly: true,
                value: _members.isEmpty
                    ? 'No members'
                    : _members.map((id) => byId[id]?.name ?? id).join(', '),
                onTap: () => _pickMembers(members),
              ),
              SizedBox(height: 6.h),
              Text(
                'Unticking a member removes them from the team when you save.',
                style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder),
              ),
              SizedBox(height: 20.h),
              PrimaryButton(
                label: _saving ? 'Saving…' : 'Save changes',
                icon: PhosphorIconsBold.check,
                height: 48,
                onTap: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _pickLead(List<(String, String)> options) {
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Team lead', onClose: () => Navigator.of(ctx).pop()),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
              children: [
                for (final (value, label) in options)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _lead = value);
                      Navigator.of(ctx).pop();
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 11.h, horizontal: 6.w),
                      child: Row(
                        children: [
                          Expanded(child: Text(label, style: AppText.body())),
                          if (value == _lead)
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

  /// Multi-select over the org's members — the ticked set becomes `member_ids`,
  /// which the API applies as a full replacement of the roster.
  void _pickMembers(List<Member> members) {
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: 'Members',
              onClose: () {
                setState(() {});
                Navigator.of(ctx).pop();
              },
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
                children: [
                  if (members.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 6.w),
                      child: Text(
                        'No teammates have loaded yet.',
                        style: AppText.body(color: AppColors.textMuted),
                      ),
                    ),
                  for (final m in members)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setSheetState(() {
                        _members.contains(m.id)
                            ? _members.remove(m.id)
                            : _members.add(m.id);
                      }),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 11.h, horizontal: 6.w),
                        child: Row(
                          children: [
                            Expanded(child: Text(m.name, style: AppText.body())),
                            if (_members.contains(m.id))
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
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }
}
