import 'package:flutter/material.dart';

/// A photo/file attached to a note (#13).
///
/// Carries one of two things depending on which side it came from:
/// - **picked on the device** — [localPath] points at the file to upload, and
///   [url] is null until the upload returns;
/// - **loaded from the API** — [url] is the CDN link and [localPath] is null.
class NoteAttachment {
  const NoteAttachment({
    required this.name,
    required this.kind,
    this.size,
    this.url,
    this.localPath,
  });

  /// 'image' or 'file'.
  final String kind;
  final String name;
  final String? size;
  final String? url;

  /// Absolute path to the picked file, set only before upload. The presence of
  /// this is what tells the notifier there is something to send.
  final String? localPath;

  bool get isImage => kind == 'image';

  /// Whether this attachment still needs uploading.
  bool get isPending => localPath != null && url == null;

  NoteAttachment copyWith({String? url, String? localPath}) => NoteAttachment(
        name: name,
        kind: kind,
        size: size,
        url: url ?? this.url,
        localPath: localPath,
      );
}

/// A reply beneath a note.
class NoteReply {
  const NoteReply({
    required this.author,
    required this.time,
    required this.body,
    this.avatarColor,
  });

  final String author;
  final String time;
  final String body;
  final Color? avatarColor;

  String get initials => _initials(author);
}

/// A single note in a record's Notes thread. Shared across every module so
/// notes look and behave identically everywhere (#13).
class NoteEntry {
  NoteEntry({
    required this.id,
    required this.author,
    required this.time,
    required this.body,
    this.via,
    this.avatarColor,
    List<NoteReply>? replies,
    List<NoteAttachment>? attachments,
  })  : replies = replies ?? [],
        attachments = attachments ?? [];

  final String id;
  final String author;
  final String time;
  final String body;

  /// Source tag: 'Call' or 'Email' → renders a small pill. Null = plain note.
  final String? via;
  final Color? avatarColor;
  final List<NoteReply> replies;
  final List<NoteAttachment> attachments;

  String get initials => _initials(author);
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

/// The signed-in user, used as the note/reply author. Matches the prototype's
/// "MV" Manoj Varma default.
/// Who is writing — the composer avatar, and the byline on a note until the
/// thread refetches and the server's `created_by` takes over.
///
/// Deliberately has **no defaults**. It used to default to a prototype user, so
/// every notes thread in the app showed the same fake person's avatar and
/// attributed everyone's notes to them. Requiring the fields means a caller
/// cannot forget to say who is writing.
class NoteAuthor {
  const NoteAuthor({
    required this.initials,
    required this.name,
    required this.color,
  });

  final String initials;
  final String name;
  final Color color;
}
