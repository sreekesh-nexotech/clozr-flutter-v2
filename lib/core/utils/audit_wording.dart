/// Plain wording for file events in activity logs (UI/UX audit #36).
///
/// The server writes attachments as "Attachment 'x.pdf' created" — the
/// model's name. People think in files and uploads, so a summary like that
/// reads "File 'x.pdf' uploaded" (updated → renamed, deleted → deleted).
/// Every other summary is returned unchanged.
String plainAuditSummary(String summary) {
  final m = RegExp(
          r"^Attachment\s+(['‘’\x22].*['‘’\x22])\s+(created|updated|deleted)$",
          caseSensitive: false)
      .firstMatch(summary.trim());
  if (m == null) return summary;
  final verb = switch (m.group(2)!.toLowerCase()) {
    'created' => 'uploaded',
    'updated' => 'renamed',
    _ => 'deleted',
  };
  return 'File ${m.group(1)} $verb';
}

/// The verb + noun for a linked-item change: "Attachment" / "create" →
/// "Uploaded file"; null when [type] is not an attachment.
String? plainRelatedChange(String type, String action) {
  if (type.toLowerCase() != 'attachment') return null;
  return switch (action.toLowerCase()) {
    'create' || 'created' => 'Uploaded file',
    'update' || 'updated' => 'Renamed file',
    'delete' || 'deleted' => 'Deleted file',
    _ => 'Changed file',
  };
}
