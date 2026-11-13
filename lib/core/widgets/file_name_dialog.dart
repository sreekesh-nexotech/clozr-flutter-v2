import 'package:flutter/material.dart';

import '../utils/upload_rules.dart';

/// "Name this file" before an upload (the webapp's upload dialog): prefilled with
/// the file's name without its extension. Returns the typed name, null if cancelled.
///
/// [title] / [action] default to the upload wording; a rename passes
/// "Rename file" / "Save".
Future<String?> showFileNameDialog(BuildContext context, String fileName,
        {String title = 'Upload file', String action = 'Upload'}) =>
    showDialog<String>(
      context: context,
      builder: (_) =>
          _FileNameDialog(fileName: fileName, title: title, action: action),
    );

class _FileNameDialog extends StatefulWidget {
  const _FileNameDialog(
      {required this.fileName, required this.title, required this.action});
  final String fileName;
  final String title;
  final String action;

  @override
  State<_FileNameDialog> createState() => _FileNameDialogState();
}

class _FileNameDialogState extends State<_FileNameDialog> {
  late final _ctrl =
      TextEditingController(text: suggestedDisplayName(widget.fileName));
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final p = nameProblem(_ctrl.text, widget.fileName);
    if (p.isNotEmpty) {
      setState(() => _error = p);
      return;
    }
    Navigator.of(context).pop(_ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final ext = splitFileName(widget.fileName).ext;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: 'File name',
          suffixText: ext.isEmpty ? null : '.$ext',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
