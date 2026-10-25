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
  final text = [e.message, ...?e.fieldErrors?.values.expand((v) => v)].join(' ');
  return RegExp('at least one note before it can be completed', caseSensitive: false).hasMatch(text);
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
    toast.showError('Note saved. Mark the $noun as completed to finish. ${e.message}'.trim());
    return false;
  }
  toast.show(followup ? 'Follow-up completed' : 'Task completed');
  return true;
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
            TextSpan(text: 'A ${widget.noun} needs a note before it can be completed. Add how '),
            TextSpan(text: widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: _ctrl.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Add note & complete'),
        ),
      ],
    );
  }
}
