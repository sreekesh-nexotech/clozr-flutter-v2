import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// A photo/file attached to a note (#13). Simulated in the presentation layer —
/// [url] stays null until a real upload endpoint is wired.
class NoteAttachment {
  const NoteAttachment({required this.name, required this.kind, this.size, this.url});

  /// 'image' or 'file'.
  final String kind;
  final String name;
  final String? size;
  final String? url;

  bool get isImage => kind == 'image';
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
class NoteAuthor {
  const NoteAuthor({this.initials = 'MV', this.name = 'Manoj Varma', this.color = AppColors.navy});
  final String initials;
  final String name;
  final Color color;
}
