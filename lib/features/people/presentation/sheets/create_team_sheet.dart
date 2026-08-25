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

/// Opens the Create team sheet — a faithful port of the prototype's
/// `createTeam` sheet. Used by both the Teams screen create button and the
/// contextual `+`.
Future<void> showCreateTeamSheet(BuildContext context) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => const _CreateTeamSheet(),
  );
}

class _CreateTeamSheet extends ConsumerStatefulWidget {
  const _CreateTeamSheet();

  @override
  ConsumerState<_CreateTeamSheet> createState() => _CreateTeamSheetState();
}

class _CreateTeamSheetState extends ConsumerState<_CreateTeamSheet> {
  final _name = TextEditingController();
  final _zone = TextEditingController();
  String _lead = ''; // member id, '' = no lead yet

  /// Members to seed the team with — `member_ids` on create (`team-api.md`
  /// §1.2). Ordered so the sheet lists them as they were picked.
  final List<String> _members = [];

  bool _showErrors = false;

  /// True while the POST is in flight, so a second tap cannot create a second
  /// team. The name is unique per org, so the duplicate comes back as a 400
  /// rather than a second row — but the user sees a validation error for
  /// something they did once.
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _zone.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _showErrors = true);
    if (!_nameOk) {
      ref.read(toastProvider.notifier).show('Enter a team name');
      return;
    }
    final name = _name.text.trim();
    if (!ApiConfig.apiEnabled) {
      Navigator.of(context).pop();
      ref.read(toastProvider.notifier).show('Team "$name" created');
      return;
    }

    final zone = _zone.text.trim();
    setState(() => _saving = true);
    try {
      await ref.read(peopleRepositoryProvider).createTeam(
            name: name,
            description: zone.isEmpty ? null : zone,
            leadUserId: _lead.isEmpty ? null : _lead,
            // The lead is a member of their own team unless they were also
            // picked in the list — the API takes `manager_id` and `member_ids`
            // separately and does not imply one from the other.
            memberIds: {
              ..._members,
              if (_lead.isNotEmpty) _lead,
            }.toList(),
          );
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ref.read(toastProvider.notifier).showError(e.message);
      return;
    }
    if (!mounted) return;
    // `getTeams()` fetches the flat org-wide TeamMember list and groups it, so
    // this one invalidate refreshes the member counts too.
    ref.invalidate(teamsProvider);
    Navigator.of(context).pop();
    ref.read(toastProvider.notifier).show('Team "$name" created');
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider).valueOrNull ?? const [];
    final byId = ref.watch(membersByIdProvider);
    final leadOpts = <(String, String)>[
      ('', 'No lead yet'),
      for (final m in members) (m.id, m.name),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Create team', onClose: () => Navigator.of(context).pop()),
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
                value: _lead.isEmpty ? 'No lead yet' : (byId[_lead]?.name ?? _lead),
                onTap: () => _pickLead(leadOpts),
              ),
              SizedBox(height: 6.h),
              Text(
                'Team lead is a designation only — it grants no scope or permissions.',
                style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder),
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Members (optional)',
                readOnly: true,
                value: _members.isEmpty
                    ? 'No members yet'
                    : _members
                        .map((id) => byId[id]?.name ?? id)
                        .join(', '),
                onTap: () => _pickMembers(members),
              ),
              SizedBox(height: 6.h),
              Text(
                'Added with the team. You can change the roster afterwards from '
                'the team itself.',
                style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder),
              ),
              SizedBox(height: 20.h),
              PrimaryButton(
                label: _saving ? 'Creating…' : 'Create team',
                icon: PhosphorIconsBold.plus,
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

  /// Multi-select over the org's members, seeding `member_ids` on create.
  ///
  /// Its own sheet rather than [showOptionPicker] so it matches the lead picker
  /// directly above it — same row height, same tick, same chrome.
  void _pickMembers(List<Member> members) {
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        // The tick has to redraw as rows are tapped, and the parent sheet is
        // behind this one — so the list owns its own rebuilds and the parent is
        // told once, on close.
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
                              Icon(PhosphorIconsBold.check,
                                  size: 19.sp, color: AppColors.success),
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
      // Also covers a dismissal by tapping the scrim or dragging down, which
      // never reaches the close button above.
      if (mounted) setState(() {});
    });
  }
}
