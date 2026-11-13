import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/approval_rules.dart';
import '../../application/providers/approval_actions_providers.dart';
import '../../domain/entities/approval.dart';

// Webapp `DecisionDialog` + `RequestCommentDialog`, in the app's existing
// decision-dialog style (the quote discount dialog): an AlertDialog with the
// change in bold, a hint, one comment field and Cancel / confirm buttons.

class _Copy {
  const _Copy(this.title, this.confirm, this.label, this.hint, this.body);
  final String title;
  final String confirm;
  final String label;
  final String hint;
  final String body;
}

const _copy = {
  ApprovalAction.approve: _Copy(
      'Approve',
      'Approve',
      'Comment (optional)',
      'e.g. Confirmed with the customer',
      'The change applies now. Your comment goes to the activity log.'),
  ApprovalAction.reject: _Copy(
      'Reject',
      'Reject',
      'Reason',
      'e.g. Customer replied yesterday, keep following',
      'The record stays as it is. Your reason is saved as an internal note on it.'),
  ApprovalAction.escalate: _Copy(
      'Escalate',
      'Escalate',
      'Note (optional)',
      'e.g. Above my approval limit',
      'This goes to your manager. You keep read-only sight of it.'),
};

/// Approve / reject / escalate one request: asks for the note, runs the
/// action, refreshes the approvals and the record, and toasts. Returns true
/// once it went through. A withdraw has no note — use [withdrawApproval].
Future<bool> showApprovalDecisionDialog(
  BuildContext context,
  WidgetRef ref, {
  required ApprovalAction action,
  required String approvalId,
  required String module,
  required String objectId,
  String subject = 'this request',
  String change = '',
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => ApprovalNoteDialog(
      action: action,
      subject: subject,
      change: change,
      submit: (note) => runApprovalAction(ref,
          id: approvalId,
          module: module,
          objectId: objectId,
          action: action,
          note: note),
    ),
  );
  if (done != true) return false;
  ref.read(toastProvider.notifier).show(approvalDoneToast[action]!);
  return true;
}

/// Takes a pending request back. Toasts the outcome; true once withdrawn.
Future<bool> withdrawApproval(
  WidgetRef ref, {
  required String approvalId,
  required String module,
  required String objectId,
}) async {
  final api = ref.read(apiServiceProvider);
  try {
    await runApprovalAction(ref,
        id: approvalId,
        module: module,
        objectId: objectId,
        action: ApprovalAction.withdraw);
  } on AppError catch (e) {
    api.handled(e);
    if (approvalErrorIsStale(e)) invalidateApprovals(ref);
    ref.read(toastProvider.notifier).showError(approvalErrorMessage(e));
    return false;
  }
  ref
      .read(toastProvider.notifier)
      .show(approvalDoneToast[ApprovalAction.withdraw]!);
  return true;
}

/// Approve or reject several requests at once (at most [bulkDecideMax]).
/// Toasts "N done · M skipped"; returns the result, or null when cancelled.
Future<BulkDecisionResult?> showBulkDecisionDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<Approval> rows,
  required bool approve,
}) async {
  BulkDecisionResult? result;
  final n = rows.length;
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => ApprovalNoteDialog(
      action: approve ? ApprovalAction.approve : ApprovalAction.reject,
      subject: '$n ${n == 1 ? 'request' : 'requests'}',
      submit: (note) async {
        result = await runBulkDecision(ref,
            rows: rows, approve: approve, note: note);
      },
    ),
  );
  final r = result;
  if (done != true || r == null) return null;
  final toast = ref.read(toastProvider.notifier);
  if (r.skippedIds.isEmpty) {
    toast.show(bulkResultLabel(r));
  } else {
    toast.showInfo(bulkResultLabel(r));
  }
  return r;
}

/// The note dialog itself. [submit] runs the action; an `AppError` it throws
/// is shown under the field and the dialog stays open.
class ApprovalNoteDialog extends ConsumerStatefulWidget {
  const ApprovalNoteDialog({
    super.key,
    required this.action,
    required this.subject,
    required this.submit,
    this.change = '',
  });

  final ApprovalAction action;

  /// What is being decided: a record's name, or "4 requests".
  final String subject;

  /// "In progress → Completed", when it is one record.
  final String change;
  final Future<void> Function(String note) submit;

  @override
  ConsumerState<ApprovalNoteDialog> createState() => _ApprovalNoteDialogState();
}

class _ApprovalNoteDialogState extends ConsumerState<ApprovalNoteDialog> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _reject => widget.action == ApprovalAction.reject;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(apiServiceProvider);
    try {
      await widget.submit(_note.text.trim());
    } on AppError catch (e) {
      api.handled(e);
      if (approvalErrorIsStale(e)) invalidateApprovals(ref);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = approvalErrorMessage(e);
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy[widget.action]!;
    final canConfirm = !_reject || isRejectionNoteValid(_note.text);
    return AlertDialog(
      title: Text('${copy.title}: ${widget.subject}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(TextSpan(style: AppText.body(), children: [
              if (widget.change.isNotEmpty)
                TextSpan(
                    text: '${widget.change}. ',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              TextSpan(text: copy.body),
            ])),
            SizedBox(height: 12.h),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: approvalNoteMax,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: copy.label,
                hintText: copy.hint,
                helperText: _reject && !canConfirm
                    ? 'At least $rejectionNoteMin characters.'
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(_error!, style: AppText.caption(color: AppColors.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        TextButton(
          onPressed: _busy || !canConfirm ? null : _confirm,
          child: Text(
            _busy ? 'Saving…' : copy.confirm,
            style: TextStyle(
                color:
                    _reject && canConfirm && !_busy ? AppColors.error : null),
          ),
        ),
      ],
    );
  }
}

/// "This needs approval" — the optional comment for the approver, asked
/// before a save that will wait. Returns the comment ('' when none was
/// written), or null when the person cancelled and nothing should be saved.
Future<String?> askApprovalRequestComment(
        BuildContext context, String change) =>
    showDialog<String>(
      context: context,
      builder: (_) => _RequestCommentDialog(change: change),
    );

class _RequestCommentDialog extends StatefulWidget {
  const _RequestCommentDialog({required this.change});

  final String change;

  @override
  State<_RequestCommentDialog> createState() => _RequestCommentDialogState();
}

class _RequestCommentDialogState extends State<_RequestCommentDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('This needs approval'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(TextSpan(style: AppText.body(), children: [
              TextSpan(
                  text: widget.change,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const TextSpan(
                  text:
                      ' waits for an approver. The record stays as it is until then, and you can keep working on it.'),
            ])),
            SizedBox(height: 12.h),
            TextField(
              controller: _note,
              maxLength: approvalNoteMax,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comment for the approver (optional)',
                hintText: 'e.g. Customer confirmed by phone',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.of(context).pop(_note.text.trim()),
            child: const Text('Send for approval')),
      ],
    );
  }
}
