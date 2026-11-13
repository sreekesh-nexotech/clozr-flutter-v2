import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';

// The webapp's `CloseTaskNoteModal`: an org can require a note before a task
// or follow-up is completed. The server refuses the status change with "A task
// must have at least one note before it can be completed."; the user writes the
// note, it is posted to the task, and the completion is retried.

/// Whether [e] is the server's "add a note first" refusal.
bool needsClosingNote(AppError e) {
  final text =
      [e.message, ...?e.fieldErrors?.values.expand((v) => v)].join(' ');
  return RegExp('at least one note before it can be completed',
          caseSensitive: false)
      .hasMatch(text);
}

/// Asks for the closing note, posts it to [taskId], then runs [complete].
/// Returns true once completed. A note that saved but whose completion failed
/// is kept, and the user is told to finish from the task.
Future<bool> completeWithClosingNote(
  BuildContext context,
  WidgetRef ref, {
  required String taskId,
  required String title,
  required bool followup,
  required Future<void> Function() complete,
  AppError? cause,
}) async {
  // The prompt explains the refusal; the shell's raw toast would repeat it.
  if (cause != null) ref.read(apiServiceProvider).handled(cause);
  final noun = followup ? 'follow-up' : 'task';
  final note = await showDialog<String>(
    context: context,
    builder: (ctx) => _ClosingNoteDialog(title: title, noun: noun),
  );
  if (note == null || note.trim().isEmpty) return false;
  final toast = ref.read(toastProvider.notifier);
  try {
    await ref.read(apiServiceProvider).post(ApiEndpoints.notes, body: {
      'content': note.trim(),
      'related_to': 'task',
      'related_to_id': taskId,
    });
  } on AppError catch (e) {
    toast.showError(e.message.isEmpty ? 'Could not save the note.' : e.message);
    return false;
  }
  try {
    await complete();
  } on AppError catch (e) {
    toast.showError(
        'Note saved. Mark the $noun as completed to finish. ${e.message}'
            .trim());
    return false;
  }
  toast.show(followup ? 'Follow-up completed' : 'Task completed');
  return true;
}

/// The Operations twin of the CRM rule (webapp `useProjectTaskCloseGate`,
/// parity C14): before an Ops task / subtask is completed, make sure it has a
/// note — unless the org lets tasks close without remarks
/// (`/crm/task-settings/` › `close_without_remarks`). With no note, the
/// “Add a closing note” dialog asks for one and posts it to the task.
///
/// Returns true to go ahead with the completion (the approval comment, if
/// any, is asked after this), false when the person cancelled. When the
/// setting or the notes cannot be read, the save goes ahead — the server has
/// the final word, as on the web.
Future<bool> ensureOpsClosingNote(
  BuildContext context,
  WidgetRef ref, {
  required String taskId,
  required String title,
}) async {
  final api = ref.read(apiServiceProvider);
  try {
    final settings = await api.get('/crm/task-settings/', quiet: true);
    if (settings is Map && settings['close_without_remarks'] == true) {
      return true;
    }
    final notes = await api.get(ApiEndpoints.notes,
        query: {
          'related_to': 'project_task',
          'related_to_id': taskId,
          'page_size': 1,
        },
        quiet: true);
    final count = notes is Map
        ? ((notes['count'] as num?)?.toInt() ??
            ((notes['results'] as List?)?.length ?? 0))
        : (notes is List ? notes.length : 0);
    if (count > 0) return true;
  } on Object {
    return true;
  }
  if (!context.mounted) return false;
  final note = await showDialog<String>(
    context: context,
    builder: (ctx) => _ClosingNoteDialog(title: title, noun: 'task'),
  );
  if (note == null || note.trim().isEmpty) return false;
  try {
    await api.post(ApiEndpoints.notes, body: {
      'content': note.trim(),
      'related_to': 'project_task',
      'related_to_id': taskId,
    });
    return true;
  } on AppError catch (e) {
    api.handled(e);
    ref
        .read(toastProvider.notifier)
        .showError(e.message.isEmpty ? 'Could not save the note.' : e.message);
    return false;
  }
}

class _ClosingNoteDialog extends StatefulWidget {
  const _ClosingNoteDialog({required this.title, required this.noun});

  final String title;
  final String noun;

  @override
  State<_ClosingNoteDialog> createState() => _ClosingNoteDialogState();
}

class _ClosingNoteDialogState extends State<_ClosingNoteDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a closing note'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: [
            TextSpan(
                text:
                    'A ${widget.noun} needs a note before it can be completed. Add how '),
            TextSpan(
                text: widget.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' went.'),
          ])),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Outcome, next steps, anything worth remembering…',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(
          onPressed: _ctrl.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Add note & complete'),
        ),
      ],
    );
  }
}
