/// The upload rules the webapp enforces before anything is sent
/// (`uploadRules.ts`): accepted types, non-empty, at most 10 MB, a name.
const kUploadExtensions = [
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'pdf', 'xlsx', 'xls', 'csv', 'md', //
  'txt', 'docx', 'pptx',
];
const kUploadMaxBytes = 10 * 1024 * 1024;
const kMaxAttachmentName = 255;

String formatUploadBytes(int bytes) {
  if (bytes < 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb >= 10 ? mb.round() : mb.toStringAsFixed(1)} MB';
}

/// `report.final.PDF` → (`report.final`, `pdf`); no extension → ext ''.
({String base, String ext}) splitFileName(String name) {
  final t = name.trim();
  final dot = t.lastIndexOf('.');
  if (dot <= 0 || dot == t.length - 1) return (base: t, ext: '');
  return (base: t.substring(0, dot), ext: t.substring(dot + 1).toLowerCase());
}

/// The name a picked file is offered under (without its extension).
String suggestedDisplayName(String fileName) {
  final base = splitFileName(fileName).base;
  final n = (base.isEmpty ? fileName : base).trim();
  return n.length > kMaxAttachmentName ? n.substring(0, kMaxAttachmentName) : n;
}

/// The stored name: what was typed, plus the file's extension when left off.
String storedFileName(String typed, String fileName) {
  final name = typed.trim();
  final ext = splitFileName(fileName).ext;
  if (ext.isEmpty || name.toLowerCase().endsWith('.$ext')) return name;
  return '$name.$ext';
}

/// Why the picked file cannot be uploaded ('' = it can).
String fileProblem(String fileName, int size) {
  final ext = splitFileName(fileName).ext;
  if (ext.isEmpty || !kUploadExtensions.contains(ext)) {
    return 'This file type is not accepted. Accepted: ${kUploadExtensions.join(', ')}.';
  }
  if (size == 0) return 'This file is empty.';
  if (size > kUploadMaxBytes) {
    final limit = formatUploadBytes(kUploadMaxBytes);
    final label = formatUploadBytes(size);
    return 'This file is ${label == limit ? '${(size / (1024 * 1024)).toStringAsFixed(2)} MB' : label}. The limit is $limit per file.';
  }
  return '';
}

/// Why the typed name cannot be used ('' = it can).
String nameProblem(String typed, String fileName) {
  final name = typed.trim();
  if (name.isEmpty) return 'Give the file a name.';
  if (storedFileName(name, fileName).length > kMaxAttachmentName) {
    return 'The name may be at most $kMaxAttachmentName characters.';
  }
  return '';
}
