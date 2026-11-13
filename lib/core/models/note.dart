import 'package:flutter/material.dart';

/// A photo/file attached to a note (#13).
///
/// Carries one of two things depending on which side it came from:
/// - **picked on the device** — [localPath] points at the file to upload, and
///   [url] is null until the upload returns;
/// - **loaded from the API** — [url] is the CDN link and [localPath] is null.
/// One of the org's note types (source tags) — `GET /crm/note-types/`.
/// [color] is the server's hex (`#16a34a`), empty when it has none.
typedef NoteTypeOption = ({String id, String name, String color});

class NoteAttachment {
  const NoteAttachment({
    required this.name,
    required this.kind,
    this.size,
    this.url,
    this.localPath,
    this.failed = false,
    this.id,
    this.localId,
  });

  /// The server's `attachment_id` once the file is stored. A note's text
  /// refers to it as `[[att:<id>]]` (see [attMarker]).
  final String? id;

  /// Temporary id the marker carries in a note's text between the moment the
  /// file is inserted and the moment its upload returns a real [id].
  final String? localId;

  /// The id this attachment's marker uses in the note text.
  String? get markerId => id ?? localId;

  /// 'image' or 'file'.
  final String kind;
  final String name;
  final String? size;
  final String? url;

  /// Absolute path to the picked file, set only before upload. The presence of
  /// this is what tells the notifier there is something to send.
  final String? localPath;

  /// Set when the upload this attachment was queued for came back an error
  /// (timed out, rejected, connection dropped) — the note itself still posted,
  /// but this file never reached the server. Kept distinct from [isPending] so
  /// the thread can say so instead of rendering it identically to a file that
  /// simply hasn't been sent yet.
  final bool failed;

  bool get isImage => kind == 'image';

  /// Whether this attachment still needs uploading.
  bool get isPending => localPath != null && url == null;

  NoteAttachment copyWith(
          {String? url, String? localPath, bool? failed, String? id}) =>
      NoteAttachment(
        name: name,
        kind: kind,
        size: size,
        url: url ?? this.url,
        localPath: localPath,
        failed: failed ?? this.failed,
        id: id ?? this.id,
        localId: localId,
      );
}

/// One placeholder character stands for each inline attachment while a note is
/// being written (U+FFFC, the object replacement character).
const String kAttObject = '\uFFFC';

/// The text a note stores where attachment [id] sits — the webapp's format, so
/// a note reads the same on both clients.
String attMarker(String id) => '[[att:$id]]';

final RegExp _attMarkerRe = RegExp(r'\[\[att:([A-Za-z0-9_-]+)\]\]');

/// A run of a note's text, or the attachment that sits between two runs.
typedef NoteContentPiece = ({String? text, String? attId});

/// [body] split into text runs and `[[att:<id>]]` markers, in order.
List<NoteContentPiece> splitNoteContent(String body) {
  final out = <NoteContentPiece>[];
  var last = 0;
  for (final m in _attMarkerRe.allMatches(body)) {
    if (m.start > last) {
      out.add((text: body.substring(last, m.start), attId: null));
    }
    out.add((text: null, attId: m.group(1)));
    last = m.end;
  }
  if (last < body.length) out.add((text: body.substring(last), attId: null));
  return out;
}

/// Whether [body] has any attachment marker.
bool noteHasAttMarkers(String body) => _attMarkerRe.hasMatch(body);

/// [body] with each marker rewritten through [idMap]: a mapped id swaps in
/// its real id, a null entry removes the marker, an unlisted id stays.
String resolveAttMarkers(String body, Map<String, String?> idMap) =>
    body.replaceAllMapped(_attMarkerRe, (m) {
      final id = m.group(1)!;
      if (!idMap.containsKey(id)) return m.group(0)!;
      final next = idMap[id];
      return next == null ? '' : attMarker(next);
    });

/// After a new note's files have uploaded: the note text with its temporary
/// markers swapped for the real attachment ids (a failed upload loses its
/// marker, the chip stays below the text flagged as failed). Null when the
/// text did not change and so needs no second write.
String? bodyAfterUploads(
    String body, List<NoteAttachment> uploaded, List<NoteAttachment> original) {
  if (!noteHasAttMarkers(body)) return null;
  final map = <String, String?>{};
  for (var i = 0; i < original.length; i++) {
    final local = original[i].localId;
    if (local == null) continue;
    final done = i < uploaded.length ? uploaded[i] : null;
    map[local] = done != null && !done.failed ? done.id : null;
  }
  var next = resolveAttMarkers(body, map);
  if (next == body) return null;
  if (next.trim().isEmpty) next = kAttachmentOnlyNoteBody;
  return next;
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
    this.pinned = false,
    this.authorId,
    this.noteType,
    List<NoteReply>? replies,
    List<NoteAttachment>? attachments,
  })  : replies = replies ?? [],
        attachments = attachments ?? [];

  final String id;

  /// `created_by.user_id` — only the author may pin, edit or delete a note
  /// (webapp `NoteCard`). Null for a note written in this session.
  final String? authorId;

  /// The org note type ("General", "Meeting", …) the note is tagged with.
  final String? noteType;
  final String author;
  final String time;
  final String body;

  /// Source tag: 'Call' or 'Email' → renders a small pill. Null = plain note.
  final String? via;
  final Color? avatarColor;

  /// Whether this note is pinned to the top of its thread.
  ///
  /// The API stores it as an **integer** `is_pinned` (0/1), not a bool — see
  /// [NotesRemoteDataSource.setPinned].
  final bool pinned;
  final List<NoteReply> replies;
  final List<NoteAttachment> attachments;

  String get initials => _initials(author);

  /// The same note with [pinned] flipped to [value]; every other field, and
  /// the live `replies`/`attachments` lists, carried over untouched.
  NoteEntry withPinned(bool value) => copyWith(pinned: value);

  NoteEntry copyWith(
          {bool? pinned, String? body, String? id, String? noteType}) =>
      NoteEntry(
        id: id ?? this.id,
        author: author,
        time: time,
        body: body ?? this.body,
        via: via,
        avatarColor: avatarColor,
        pinned: pinned ?? this.pinned,
        authorId: authorId,
        noteType: noteType ?? this.noteType,
        replies: replies,
        attachments: attachments,
      );
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
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

/// Content stored for a note whose whole payload is an attachment.
///
/// `POST /crm/notes/` rejects a blank `content` outright —
/// `{"content": ["This field may not be blank."]}` — and DRF trims the value
/// before that check, so whitespace is refused too (a single space returns 400;
/// verified against the live dev org). A photo posted with no caption therefore
/// has to carry *something*, or the note is never created and the attachment,
/// which uploads against the created note's id, is never sent either.
const String kAttachmentOnlyNoteBody = '📎';

/// [body] as it should be stored: unchanged, unless it is empty and the note
/// exists only to carry [attachments], in which case the placeholder stands in.
///
/// Applied to the optimistic entry *and* the POST so the thread reads the same
/// before and after a refetch.
String noteBodyForApi(String body, List<NoteAttachment> attachments) =>
    body.trim().isEmpty && attachments.isNotEmpty
        ? kAttachmentOnlyNoteBody
        : body.trim();
