import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/customer_activity_view.dart';
import '../../application/providers/customer_activity_tabs_providers.dart';
import 'add_sheet_kit.dart';
import 'linked_record_banner.dart';

/// Add call log on a customer — the webapp's `AddCustomerCallLogModal`:
/// From / To (required, "From and To numbers are required."), Direction,
/// Medium (Manual / Twilio / Exotel) and an optional HH:MM:SS duration, posted
/// to `/crm/call-logs/` with `related_to=customer`. Success toasts "Call logged".
///
/// Returns true when a call was logged, so the caller refreshes its tab.
Future<bool> showAddCustomerCallLogSheet(
  BuildContext context, {
  required String customerId,
  required String customerName,
  String customerPhone = '',
}) async {
  final saved = await showClozrSheet<bool>(
    context: context,
    builder: (_) => _AddCustomerCallLogSheet(
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
    ),
  );
  return saved ?? false;
}

class _AddCustomerCallLogSheet extends ConsumerStatefulWidget {
  const _AddCustomerCallLogSheet({
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
  });

  final String customerId;
  final String customerName;
  final String customerPhone;

  @override
  ConsumerState<_AddCustomerCallLogSheet> createState() => _AddCustomerCallLogSheetState();
}

class _AddCustomerCallLogSheetState extends ConsumerState<_AddCustomerCallLogSheet> {
  static const _mediums = ['Manual', 'Twilio', 'Exotel'];

  late final _from = TextEditingController(
      text: ref.read(sessionControllerProvider).user?.phone.trim() ?? '');
  late final _to = TextEditingController(text: widget.customerPhone.trim());
  final _duration = TextEditingController();
  String _direction = 'Outgoing';
  String _medium = 'Manual';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_from, _to, _duration]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final toast = ref.read(toastProvider.notifier);
    final problem = validateCustomerCallLog(from: _from.text, to: _to.text, duration: _duration.text);
    if (problem != null) {
      setState(() => _error = problem);
      toast.showError(problem);
      return;
    }
    if (!ApiConfig.apiEnabled) {
      toast.show('Call logs save once the app is connected to the API.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await createCustomerCallLog(
        ref.read(apiServiceProvider),
        customerId: widget.customerId,
        from: _from.text,
        to: _to.text,
        direction: _direction,
        medium: _medium,
        duration: _duration.text,
      );
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(apiServiceProvider).handled(e);
      final msg = e.message.isEmpty ? 'Could not log the call.' : e.message;
      setState(() {
        _saving = false;
        _error = msg;
      });
      toast.showError(msg);
      return;
    }
    toast.show('Call logged');
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final numbersMissing = _error == callLogNumbersRequired;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Add call log', onClose: () => Navigator.of(context).pop(false)),
        Flexible(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinkedRecordBanner(label: widget.customerName),
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'From number',
                        required: true,
                        controller: _from,
                        hint: '+91…',
                        keyboardType: TextInputType.phone,
                        errorText: numbersMissing && _from.text.trim().isEmpty ? callLogNumbersRequired : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: AppTextField(
                        label: 'To number',
                        required: true,
                        controller: _to,
                        hint: '+91…',
                        keyboardType: TextInputType.phone,
                        errorText: numbersMissing && _to.text.trim().isEmpty ? callLogNumbersRequired : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                const SheetFieldLabel('Direction'),
                Wrap(spacing: 8.w, runSpacing: 8.h, children: [
                  for (final d in const ['Outgoing', 'Incoming'])
                    SelectChip(label: d, selected: _direction == d, onTap: () => setState(() => _direction = d)),
                ]),
                SizedBox(height: 16.h),
                const SheetFieldLabel('Medium'),
                Wrap(spacing: 8.w, runSpacing: 8.h, children: [
                  for (final m in _mediums)
                    SelectChip(label: m, selected: _medium == m, onTap: () => setState(() => _medium = m)),
                ]),
                SizedBox(height: 16.h),
                AppTextField(
                  label: 'Duration (optional)',
                  controller: _duration,
                  hint: 'HH:MM:SS — e.g. 00:03:20',
                  keyboardType: TextInputType.datetime,
                  errorText: _error == callLogDurationInvalid ? callLogDurationInvalid : null,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
        ),
        SheetSubmitBar(
          label: 'Log call',
          icon: PhosphorIconsBold.phone,
          busy: _saving,
          busyLabel: 'Saving…',
          onTap: _submit,
        ),
      ],
    );
  }
}
