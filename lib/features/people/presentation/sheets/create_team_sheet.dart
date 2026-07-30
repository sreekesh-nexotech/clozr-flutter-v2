import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/people_providers.dart';

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
  bool _showErrors = false;

  @override
  void dispose() {
    _name.dispose();
    _zone.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;

  void _submit() {
    setState(() => _showErrors = true);
    if (!_nameOk) {
      ref.read(toastProvider.notifier).show('Enter a team name');
      return;
    }
    Navigator.of(context).pop();
    ref.read(toastProvider.notifier).show('Team "${_name.text.trim()}" created');
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
              SizedBox(height: 20.h),
              PrimaryButton(
                label: 'Create team',
                icon: PhosphorIconsBold.plus,
                height: 48,
                onTap: _submit,
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
}
