import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';

// The webapp's due-date change flow (`useDueDateChangeFlow`,
// `DueDateReasonModal`, `PendingDueDateBanner`, `DueDateDecisionDialog`).
// Moving an existing due date can need a reason; past the self-service limit
// the server answers 202 and the change waits for a manager.

/// The org's due-date rules from `GET /settings/sla/`, or null when this user
/// cannot read them (the server's 400 then opens the reason prompt instead).
final dueDateRulesProvider = FutureProvider.autoDispose<({bool reasonRequired, List<String> reasons})?>((ref) async {
  try {
    final body = await ref.read(apiServiceProvider).get('/settings/sla/', quiet: true);
    final d = body is Map ? (body['data'] is Map ? body['data'] as Map : body) : const {};
    final rules = d['due_date'] is Map ? d['due_date'] as Map : const {};
    return (
      reasonRequired: rules['reason_required'] == true,
      reasons: [for (final r in (rules['reasons'] is List ? rules['reasons'] as List : const [])) '$r'],
    );
  } on Object {
    return null;
  }
});

/// Webapp `reasonOptions`: configured reasons trimmed and de-duplicated, with
/// "Other" always last.
List<String> dueDateReasonOptions(List<String> configured) {
  final out = <String>[];
  for (final r in configured) {
    final t = r.trim();
    if (t.isEmpty || t.toLowerCase() == 'other' || out.contains(t)) continue;
    out.add(t);
  }
  return [...out, 'Other'];
}

/// "18 Jun 2026" from `YYYY-MM-DD` (or an ISO timestamp — only its date part).
String dueDateLabel(String? raw) {
  final s = (raw ?? '').trim();
  if (s.length < 10) return s;
  final d = DateTime.tryParse(s.substring(0, 10));
  if (d == null) return s;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// "+4 days" / "-1 day" / "No slip".
String slipLabel(num? days) {
  final n = (days ?? 0).toInt();
  if (n == 0) return 'No slip';
  final sign = n > 0 ? '+' : '-';
  return '$sign${n.abs()} ${n.abs() == 1 ? 'day' : 'days'}';
}

/// Webapp `rescheduleLabel`: "Moved 2×, +4 days"; null when never moved.
String? rescheduleLabel(Map<String, dynamic>? row) {
  final count = (row?['reschedule_count'] as num?)?.toInt() ?? 0;
  if (count == 0) return null;
  final slip = (row?['slip_days'] as num?)?.toInt() ?? 0;
  final days = slip == 0 ? '±0 days' : '${slip > 0 ? '+' : '-'}${slip.abs()} ${slip.abs() == 1 ? 'day' : 'days'}';
  return 'Moved $count×, $days';
}

enum DueDateWrite { saved, pending, cancelled }

/// Sends [fields] through the due-date flow. When [fields] moves an existing
/// date ([dateKey] present and [hadDate]) and the org requires a reason, asks
/// first; a server `due_date_reason_required` refusal asks too and retries.
/// Toasts "Sent to your manager for approval" on 202. Other errors are thrown.
Future<DueDateWrite> writeWithDueDateFlow(
  BuildContext context,
  WidgetRef ref, {
  required String path,
  required Map<String, dynamic> fields,
  required bool hadDate,
  String dateKey = 'due_date',
  String fieldLabel = 'Due date',
}) async {
  var body = {...fields};
  final moving = body.containsKey(dateKey) && hadDate;
  if (moving) {
    final rules = await ref.read(dueDateRulesProvider.future);
    if (rules != null && rules.reasonRequired) {
      if (!context.mounted) return DueDateWrite.cancelled;
      final reason = await showDueDateReasonSheet(context,
          fieldLabel: fieldLabel, newDate: body[dateKey]?.toString(), reasons: rules.reasons);
      if (reason == null) return DueDateWrite.cancelled;
      body = {...body, ...reason};
    }
  }
  final api = ref.read(apiServiceProvider);
  try {
    final (status, _) = await api.patchWithStatus(path, body: body);
    if (status == 202) {
      ref.read(toastProvider.notifier).show('Sent to your manager for approval');
      return DueDateWrite.pending;
    }
    return DueDateWrite.saved;
  } on AppError catch (e) {
    final code = e.code ?? '${e.extra?['code'] ?? ''}';
    if (code != 'due_date_reason_required' || body.containsKey('due_date_change_reason')) rethrow;
    api.handled(e);
    final serverReasons = [for (final r in (e.extra?['reasons'] is List ? e.extra!['reasons'] as List : const [])) '$r'];
    if (!context.mounted) return DueDateWrite.cancelled;
    final reason = await showDueDateReasonSheet(context,
        fieldLabel: fieldLabel, newDate: body[dateKey]?.toString(), reasons: serverReasons);
    if (reason == null) return DueDateWrite.cancelled;
    final (status, _) = await api.patchWithStatus(path, body: {...body, ...reason});
    if (status == 202) {
      ref.read(toastProvider.notifier).show('Sent to your manager for approval');
      return DueDateWrite.pending;
    }
    return DueDateWrite.saved;
  }
}

/// "Why is the due date moving?" — returns the reason keys to send, or null.
Future<Map<String, dynamic>?> showDueDateReasonSheet(
  BuildContext context, {
  required String fieldLabel,
  required String? newDate,
  required List<String> reasons,
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ReasonDialog(fieldLabel: fieldLabel, newDate: newDate, reasons: dueDateReasonOptions(reasons)),
    );

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.fieldLabel, required this.newDate, required this.reasons});

  final String fieldLabel;
  final String? newDate;
  final List<String> reasons;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _note = TextEditingController();
  String? _reason;
  String? _reasonError;
  String? _noteError;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _other => _reason == 'Other';

  void _submit() {
    setState(() {
      _reasonError = _reason == null ? 'Pick a reason.' : null;
      _noteError = _other && _note.text.trim().isEmpty ? 'Say what the reason is.' : null;
    });
    if (_reasonError != null || _noteError != null) return;
    Navigator.of(context).pop({
      'due_date_change_reason': _reason,
      'due_date_change_note': _note.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.fieldLabel.toLowerCase();
    final date = (widget.newDate ?? '').isEmpty
        ? (field.contains('committed') ? 'no committed date' : 'no due date')
        : dueDateLabel(widget.newDate);
    return AlertDialog(
      title: Text('Why is the $field moving?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: 'The $field will move to '),
              TextSpan(text: date, style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: '. The committed date stays as it is; the reason is kept on the record’s history.'),
            ])),
            SizedBox(height: 12.h),
            Text('Reason *', style: AppText.captionStrong()),
            SizedBox(height: 4.h),
            DropdownButtonFormField<String>(
              value: _reason,
              isExpanded: true,
              hint: const Text('Pick a reason'),
              items: [for (final r in widget.reasons) DropdownMenuItem(value: r, child: Text(r))],
              onChanged: (v) => setState(() {
                _reason = v;
                _reasonError = null;
              }),
              decoration: InputDecoration(errorText: _reasonError, border: const OutlineInputBorder(), isDense: true),
            ),
            SizedBox(height: 12.h),
            Text(_other ? 'Note *' : 'Note (optional)', style: AppText.captionStrong()),
            SizedBox(height: 4.h),
            TextField(
              controller: _note,
              maxLength: 2000,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() => _noteError = null),
              decoration: InputDecoration(
                hintText: _other ? 'Say what the reason is' : 'Anything the approver should know',
                errorText: _noteError,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: Text('Move $field')),
      ],
    );
  }
}

/// Webapp `PendingDueDateBanner`, from the record's `pending_due_date_change`.
class PendingDueDateBanner extends StatelessWidget {
  const PendingDueDateBanner({super.key, required this.pending});

  final Map<String, dynamic>? pending;

  @override
  Widget build(BuildContext context) {
    final p = pending;
    if (p == null || p['status'] != 'pending') return const SizedBox.shrink();
    final slip = p['slip_days'] as num?;
    final reason = '${p['reason_code'] ?? ''}'.trim();
    final note = '${p['reason_text'] ?? ''}'.trim();
    final who = '${p['requested_by_name'] ?? ''}'.trim();
    final rest = StringBuffer('Due date → ${dueDateLabel('${p['new_value'] ?? ''}')}');
    if (slip != null && slip != 0) rest.write(' (${slipLabel(slip)})');
    if (reason.isNotEmpty) rest.write(' — $reason');
    if (note.isNotEmpty) rest.write(': “$note”');
    if (who.isNotEmpty) rest.write(' · requested by $who');
    if ('${p['created_at'] ?? ''}'.isNotEmpty) rest.write(' on ${dueDateLabel('${p['created_at']}')}');
    rest.write('. The current date stays until it is decided.');
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 14.h),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(color: AppColors.tintAmber, borderRadius: BorderRadius.circular(12.r)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(PhosphorIconsRegular.hourglassMedium, size: 16.sp, color: AppColors.warningDeep),
        SizedBox(width: 8.w),
        Expanded(
          child: Text.rich(TextSpan(style: AppText.body(), children: [
            const TextSpan(text: 'Sent to your manager for approval. ', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: rest.toString()),
          ])),
        ),
      ]),
    );
  }
}

/// Webapp `DueDateDecisionDialog`. Returns true once decided.
Future<bool> decideDueDateChange(BuildContext context, WidgetRef ref, Map<String, dynamic> change, {required bool approve}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _DecisionDialog(change: change, approve: approve),
  );
  if (done != true) return false;
  ref.read(toastProvider.notifier).show(approve ? 'Due-date change approved' : 'Due-date change rejected');
  return true;
}

class _DecisionDialog extends ConsumerStatefulWidget {
  const _DecisionDialog({required this.change, required this.approve});

  final Map<String, dynamic> change;
  final bool approve;

  @override
  ConsumerState<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends ConsumerState<_DecisionDialog> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final id = '${widget.change['change_id']}';
    final api = ref.read(apiServiceProvider);
    try {
      await api.post('/sla/due-date-changes/$id/${widget.approve ? 'approve' : 'reject'}/', body: {'note': _note.text.trim()});
    } on AppError catch (e) {
      api.handled(e);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.change;
    final who = '${c['requested_by_name'] ?? ''}'.trim();
    final field = '${c['field'] ?? ''}'.replaceAll('_', ' ').trim();
    final slip = c['slip_days'] as num?;
    final reason = '${c['reason_code'] ?? ''}'.trim();
    final note = '${c['reason_text'] ?? ''}'.trim();
    final tail = StringBuffer();
    if (slip != null && slip != 0) tail.write(' (${slipLabel(slip)})');
    if (reason.isNotEmpty) tail.write(' — $reason');
    if (note.isNotEmpty) tail.write(': “$note”');
    tail.write('. ');
    tail.write(widget.approve
        ? 'Approving moves the working date; the committed date stays.'
        : 'Rejecting keeps the current date.');
    return AlertDialog(
      title: Text(widget.approve ? 'Approve this due-date change?' : 'Reject this due-date change?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: who.isEmpty ? 'The requester' : who, style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' wants the ${field.isEmpty ? 'due date' : field} moved from ${dueDateLabel('${c['old_value'] ?? ''}')} to '),
            TextSpan(text: dueDateLabel('${c['new_value'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: tail.toString()),
          ])),
          SizedBox(height: 12.h),
          TextField(
            controller: _note,
            maxLength: 2000,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              hintText: widget.approve ? 'e.g. OK — client confirmed the new date' : 'e.g. Keep the date; pull in help instead',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) Text(_error!, style: AppText.caption(color: AppColors.error)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Saving…' : (widget.approve ? 'Approve change' : 'Reject change'),
              style: TextStyle(color: widget.approve ? null : AppColors.error)),
        ),
      ],
    );
  }
}
