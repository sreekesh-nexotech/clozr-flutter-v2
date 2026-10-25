import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/call_logs_providers.dart';
import '../../domain/entities/call_log.dart';
import '../sheets/add_sheet_kit.dart';

// The webapp's per-call actions (`CallLogActions`) and "Sync from Exotel"
// (`ExotelSyncButton`) on a lead's Call log tab.

/// The actions a call offers, webapp rules: note / task while the lead takes
/// activity, Transcribe once there is a recording and no transcript,
/// Summarize once there is a transcript and no summary.
Future<void> showCallLogActions(
  BuildContext context,
  WidgetRef ref, {
  required CallLog call,
  required String leadId,
  required bool allowActivity,
  VoidCallback? onPlay,
}) async {
  final actions = <(String, IconData, Future<void> Function())>[
    if (call.hasRecording && onPlay != null)
      ('Play recording', PhosphorIconsRegular.playCircle, () async => onPlay()),
    if (allowActivity) ...[
      ('Add note', PhosphorIconsRegular.notePencil, () => _addNote(context, ref, call, leadId)),
      ('Create task', PhosphorIconsRegular.checkSquare, () => _createTask(context, ref, call, leadId)),
    ],
    if (call.hasRecording && call.transcript.isEmpty)
      ('Transcribe', PhosphorIconsRegular.textAa, () => _start(ref, ApiEndpoints.callLogTranscribe(call.id), 'Transcription started — it will appear shortly', leadId)),
    if (call.transcript.isNotEmpty && call.summary.isEmpty)
      ('Summarize', PhosphorIconsRegular.sparkle, () => _start(ref, ApiEndpoints.callLogSummarize(call.id), 'Summary started — it will appear shortly', leadId)),
  ];
  if (actions.isEmpty) return;
  final picked = await showClozrSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: call.outcome, onClose: () => Navigator.of(ctx).pop()),
          for (var i = 0; i < actions.length; i++)
            ListTile(
              leading: Icon(actions[i].$2, size: 20.sp, color: AppColors.navy),
              title: Text(actions[i].$1, style: AppText.bodyStrong()),
              onTap: () => Navigator.of(ctx).pop(i),
            ),
          SizedBox(height: 8.h),
        ],
      ),
    ),
  );
  if (picked == null) return;
  await actions[picked].$3();
}

Future<void> _addNote(BuildContext context, WidgetRef ref, CallLog call, String leadId) async {
  final text = await _askText(context, title: 'Add note', hint: 'Note about this call…');
  if (text == null) return;
  await _post(ref, ApiEndpoints.exotelCallNote(call.id), {'content': text}, 'Note added to call', leadId);
}

Future<void> _createTask(BuildContext context, WidgetRef ref, CallLog call, String leadId) async {
  final text = await _askText(context, title: 'Create task', hint: 'Follow-up task title…');
  if (text == null) return;
  await _post(ref, ApiEndpoints.exotelCallTask(call.id), {'title': text}, 'Follow-up task created', leadId);
}

Future<void> _start(WidgetRef ref, String path, String success, String leadId) =>
    _post(ref, path, const {}, success, leadId);

Future<void> _post(WidgetRef ref, String path, Map<String, dynamic> body, String success, String leadId) async {
  final toast = ref.read(toastProvider.notifier);
  try {
    await ref.read(apiServiceProvider).post(path, body: body);
  } on AppError catch (e) {
    ref.read(apiServiceProvider).handled(e);
    toast.showError(e.message);
    return;
  }
  ref.invalidate(leadCallLogsProvider(leadId));
  toast.show(success);
}

/// One line of text, like the webapp's inline input (Enter / Save).
Future<String?> _askText(BuildContext context, {required String title, required String hint}) =>
    showDialog<String>(context: context, builder: (_) => _TextDialog(title: title, hint: hint));

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final t = _ctrl.text.trim();
    if (t.isNotEmpty) Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(hintText: widget.hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _ctrl.text.trim().isEmpty ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

// ── Sync from Exotel ──

/// Webapp `ExotelSyncButton`: pulls calls made in the Exotel app into this
/// lead's log — the last 90 days, or a chosen range — then re-reads the tab a
/// few times while the server's job lands them.
Future<void> showExotelSyncSheet(BuildContext context, WidgetRef ref, {required String leadId}) async {
  final range = await showClozrSheet<(DateTime?, DateTime?)>(
    context: context,
    builder: (_) => const _SyncSheet(),
  );
  if (range == null) return;
  final toast = ref.read(toastProvider.notifier);
  try {
    final res = await ref.read(apiServiceProvider).post(ApiEndpoints.exotelSyncCalls, body: {
      'lead_id': leadId,
      if (range.$1 != null) 'from_date': sheetIsoDate(range.$1!),
      if (range.$2 != null) 'to_date': sheetIsoDate(range.$2!),
    });
    final detail = res is Map ? '${res['detail'] ?? ''}'.trim() : '';
    toast.show(detail.isEmpty ? 'Sync started — calls will appear shortly.' : detail);
  } on AppError catch (e) {
    ref.read(apiServiceProvider).handled(e);
    toast.showError(e.message);
    return;
  }
  // Webapp re-polls at 0, 2.5, 5, 8, 12 and 15 s.
  for (final ms in const [0, 2500, 5000, 8000, 12000, 15000]) {
    Timer(Duration(milliseconds: ms), () {
      try {
        ref.invalidate(leadCallLogsProvider(leadId));
      } on Object {
        // The screen has gone; nothing to refresh.
      }
    });
  }
}

class _SyncSheet extends StatefulWidget {
  const _SyncSheet();

  @override
  State<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<_SyncSheet> {
  DateTime? _from;
  DateTime? _to;
  String? _error;

  Future<void> _pick(bool from) async {
    final d = await pickSheetDate(context, from ? (_from == null ? '' : sheetIsoDate(_from!)) : (_to == null ? '' : sheetIsoDate(_to!)));
    if (d == null || !mounted) return;
    setState(() {
      from ? _from = d : _to = d;
      _error = null;
    });
  }

  Widget _dateBox(String label, DateTime? value, bool from) => Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _pick(from),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE6E7EA)),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppText.caption()),
              SizedBox(height: 2.h),
              Text(value == null ? 'Any' : sheetDateLabel(value), style: AppText.bodyStrong()),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader(title: 'Sync from Exotel', onClose: () => Navigator.of(context).pop()),
          Padding(
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 12.h),
            child: Text("Pull calls made through the Exotel app into this lead's call log (last 90 days)",
                style: AppText.body(color: AppColors.textMuted)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 18.w),
            child: Row(children: [
              _dateBox('From', _from, true),
              SizedBox(width: 10.w),
              _dateBox('To', _to, false),
            ]),
          ),
          if (_error != null)
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 0),
              child: Text(_error!, style: AppText.caption(color: AppColors.error)),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 12.h),
            child: Row(children: [
              PrimaryButton(
                label: 'Last 90 days',
                ghost: true,
                expand: false,
                height: 46,
                onTap: () => Navigator.of(context).pop((null, null)),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: PrimaryButton(
                  label: 'Sync range',
                  icon: PhosphorIconsBold.arrowsClockwise,
                  height: 46,
                  onTap: () {
                    if (_from != null && _to != null && _from!.isAfter(_to!)) {
                      setState(() => _error = '“From” must be on or before “To”.');
                      return;
                    }
                    Navigator.of(context).pop((_from, _to));
                  },
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
