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
import '../../../../core/utils/phone_rules.dart';
import '../../../../core/widgets/phone_controller.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/call_logs_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/lead.dart';
import 'add_sheet_kit.dart';

/// Log call — records a call that already happened against a lead.
///
/// This is the manual counterpart to the Call button, which dials and logs in
/// one go. Here the user says what happened after the fact: which way it went,
/// whether it connected, and for how long.
///
/// There is **no notes field**, deliberately. `call_summary` on the API is
/// server-set from transcription — it is silently dropped on create, so a notes
/// box here would look like it saved something and quietly lose it.
Future<void> showLogCallSheet(
  BuildContext context,
  WidgetRef ref, {
  required Lead lead,
}) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _LogCallSheet(ref: ref, lead: lead),
  );
}

/// How the call ended. Drives `is_missed` and whether a duration is collected.
enum _Outcome { connected, noAnswer, missed }

class _LogCallSheet extends StatefulWidget {
  const _LogCallSheet({required this.ref, required this.lead});
  final WidgetRef ref;
  final Lead lead;

  @override
  State<_LogCallSheet> createState() => _LogCallSheetState();
}

class _LogCallSheetState extends State<_LogCallSheet> {
  final _minutes = TextEditingController();
  final _seconds = TextEditingController();
  /// Prefilled with the lead's own country + national digits, split from the
  /// stored E.164 value.
  late final PhoneController _toNumber = PhoneController(initialE164: widget.lead.phone);

  bool _incoming = false;
  _Outcome _outcome = _Outcome.connected;
  bool _saving = false;
  bool _showErrors = false;

  @override
  void dispose() {
    for (final c in [_minutes, _seconds]) {
      c.dispose();
    }
    _toNumber.dispose();
    super.dispose();
  }

  /// The signed-in user's own number. The API requires `from_number`, and an
  /// account with no profile phone simply cannot log a call — so say that up
  /// front rather than letting the submit fail with a field error.
  String get _myNumber =>
      widget.ref.read(sessionControllerProvider).user?.phone.trim() ?? '';

  bool get _toOk => _toNumber.isComplete;

  Duration get _duration => Duration(
        minutes: int.tryParse(_minutes.text.trim()) ?? 0,
        seconds: int.tryParse(_seconds.text.trim()) ?? 0,
      );

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _showErrors = true);

    final toast = widget.ref.read(toastProvider.notifier);
    if (!_toOk) {
      toast.show('Enter the number that was called');
      return;
    }
    if (ApiConfig.apiEnabled && _myNumber.isEmpty) {
      toast.show('Add your phone number to your profile to log calls.');
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.ref.read(callLogsRepositoryProvider).logManualCall(
            leadId: widget.lead.id,
            fromNumber: _myNumber,
            // E.164 with the code, which is what `normaliseCallNumber` and
            // Exotel's `to_number` expect — a bare ten digits would be dialled
            // without a country.
            toNumber: _toNumber.toE164() ?? '',
            incoming: _incoming,
            isMissed: _outcome == _Outcome.missed,
            // A call that never connected has no duration to report, whatever
            // is sitting in the fields.
            duration: _outcome == _Outcome.connected ? _duration : Duration.zero,
          );
    } on AppError catch (e) {
      if (mounted) setState(() => _saving = false);
      toast.showError(e.message);
      return;
    }

    // The call list and the lead itself both moved — logging a call re-scores
    // the lead server-side.
    widget.ref.invalidate(leadCallLogsProvider(widget.lead.id));
    widget.ref.invalidate(leadDetailProvider(widget.lead.id));
    toast.show('Call logged');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final noNumber = ApiConfig.apiEnabled && _myNumber.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Log call', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: SingleChildScrollView(
            // The number field is the last one; typing there hides the
            // direction and outcome chips above it until the sheet is dragged.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinkedLeadField(lead: widget.lead),
                if (noNumber) ...[
                  SizedBox(height: 12.h),
                  Text(
                    'Your own phone number is missing from your profile. Every '
                    'call log records the caller — that is you, not the number '
                    'below — so add one to your profile before logging calls.',
                    style: AppText.custom(
                            size: 11.5, weight: FontWeight.w500, color: AppColors.error)
                        .copyWith(height: 1.4),
                  ),
                ],
                SizedBox(height: 16.h),
                const SheetFieldLabel('Direction'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    SelectChip(
                      label: 'Outgoing',
                      selected: !_incoming,
                      onTap: () => setState(() => _incoming = false),
                    ),
                    SelectChip(
                      label: 'Incoming',
                      selected: _incoming,
                      onTap: () => setState(() => _incoming = true),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                const SheetFieldLabel('Outcome'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    SelectChip(
                      label: 'Connected',
                      selected: _outcome == _Outcome.connected,
                      dot: AppColors.success,
                      onTap: () => setState(() => _outcome = _Outcome.connected),
                    ),
                    SelectChip(
                      label: 'No answer',
                      selected: _outcome == _Outcome.noAnswer,
                      dot: AppColors.textPlaceholder,
                      onTap: () => setState(() => _outcome = _Outcome.noAnswer),
                    ),
                    SelectChip(
                      label: 'Missed',
                      selected: _outcome == _Outcome.missed,
                      dot: AppColors.error,
                      onTap: () => setState(() => _outcome = _Outcome.missed),
                    ),
                  ],
                ),
                // Only a connected call has a duration worth asking for.
                if (_outcome == _Outcome.connected) ...[
                  SizedBox(height: 16.h),
                  const SheetFieldLabel('Duration'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Minutes',
                          controller: _minutes,
                          hint: '4',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: AppTextField(
                          label: 'Seconds',
                          controller: _seconds,
                          hint: '12',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: 14.h),
                PhoneInputField(
                  label: _incoming ? 'Number that called' : 'Number called',
                  required: true,
                  controller: _toNumber,
                  hint: '98470 00000',
                  errorText: _showErrors && !_toOk ? phoneDigitsMessage(_toNumber.rule) : null,
                  onChanged: () => setState(() {}),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Notes about a call go on a note — the call record itself only '
                  'stores what happened and for how long.',
                  style: AppText.custom(
                          size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)
                      .copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ),
        SheetSubmitBar(
          label: 'Log call',
          icon: PhosphorIconsBold.phone,
          busy: _saving,
          busyLabel: 'Logging…',
          onTap: _submit,
        ),
      ],
    );
  }
}
