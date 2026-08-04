import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../domain/entities/followup.dart';
import 'add_sheet_kit.dart';

/// Add follow-up — a focused-but-faithful port of the prototype's `addFollowup`
/// sheet. On submit the new follow-up is prepended to [followupDraftsProvider]
/// so it appears immediately in the list, then a toast confirms.
Future<void> showAddFollowupSheet(BuildContext context, WidgetRef ref) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _AddFollowupSheet(ref: ref),
  );
}

const _fuKinds = ['Call', 'Email', 'Meeting', 'WhatsApp', 'Site visit', 'Payment'];

class _AddFollowupSheet extends StatefulWidget {
  const _AddFollowupSheet({required this.ref});
  final WidgetRef ref;

  @override
  State<_AddFollowupSheet> createState() => _AddFollowupSheetState();
}

class _AddFollowupSheetState extends State<_AddFollowupSheet> {
  final _company = TextEditingController();
  final _contact = TextEditingController();
  final _date = TextEditingController();
  final _time = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'Call';
  bool _showErrors = false;

  @override
  void dispose() {
    for (final c in [_company, _contact, _date, _time, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _contactOk => _contact.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (!_contactOk) {
      widget.ref.read(toastProvider.notifier).show('Enter a contact name');
      return;
    }
    if (ApiConfig.apiEnabled) {
      try {
        await widget.ref.read(followupsRepositoryProvider).createFollowup({
          'title': _contact.text.trim(),
          'task_type': _kind,
          'due_date': _date.text.trim(),
          'description': _note.text.trim(),
        });
      } on AppError catch (e) {
        widget.ref.read(toastProvider.notifier).show(e.message);
        return;
      }
      widget.ref.invalidate(followupsProvider);
      widget.ref.read(toastProvider.notifier).show('Follow-up scheduled');
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final contact = _contact.text.trim();
    final company = _company.text.trim();
    final fu = Followup(
      id: genId('F'),
      kind: _kind,
      contact: contact,
      custId: null,
      leadId: null,
      company: company.isEmpty ? contact : company,
      due: _date.text.trim().isEmpty ? '09 Jul 2026' : _date.text.trim(),
      time: _time.text.trim().isEmpty ? '10:00' : _time.text.trim(),
      status: 'due',
      owner: 'me',
      agenda: _note.text.trim().isEmpty ? 'Follow-up' : _note.text.trim(),
    );
    final drafts = widget.ref.read(followupDraftsProvider);
    widget.ref.read(followupDraftsProvider.notifier).state = [fu, ...drafts];
    widget.ref.read(toastProvider.notifier).show('Follow-up scheduled');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'New follow-up', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetFieldLabel('Type'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (final k in _fuKinds)
                      SelectChip(label: k, selected: _kind == k, onTap: () => setState(() => _kind = k)),
                  ],
                ),
                SizedBox(height: 16.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: AppTextField(label: 'Company', controller: _company, hint: 'e.g. Kalyan Silks')),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: AppTextField(
                        label: 'Contact',
                        required: true,
                        controller: _contact,
                        hint: 'e.g. Sneha Kulkarni',
                        errorText: _showErrors && !_contactOk ? 'Enter a contact name' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: AppTextField(label: 'Date', controller: _date, hint: 'e.g. 22 Jun 2026')),
                    SizedBox(width: 10.w),
                    Expanded(child: AppTextField(label: 'Time', controller: _time, hint: '10:00')),
                  ],
                ),
                SizedBox(height: 14.h),
                AppTextField(label: 'Note', controller: _note, hint: "What's this follow-up about?"),
                SizedBox(height: 8.h),
                Text('Reminders need a due date.',
                    style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ],
            ),
          ),
        ),
        SheetSubmitBar(label: 'Add follow-up', icon: PhosphorIconsBold.plus, onTap: _submit),
      ],
    );
  }
}
