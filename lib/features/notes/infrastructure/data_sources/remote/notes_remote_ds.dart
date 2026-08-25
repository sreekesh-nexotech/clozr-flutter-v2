import 'package:dio/dio.dart';

import '../../../../../core/models/note.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/user_directory.dart';

/// Remote notes (`/crm/notes/`) for any record (`lead` / `customer` / `task` —
/// follow-ups pass `task` too — and `issue` for helpdesk tickets). HTTP + JSON →
/// [NoteEntry] mapping only; the notes notifier owns state and optimism.
class NotesRemoteDataSource {
  const NotesRemoteDataSource(this._api);

  final ApiService _api;

  /// Top-level notes for one record, newest-first, each with its thread
  /// hydrated.
  ///
  /// The list endpoint returns top-level notes only — a reply never appears in
  /// it — so every thread costs one extra request. Skipping them left replies
  /// visible until the app restarted and then gone, which reads as data loss.
  /// Only notes the list says have replies are fetched, and they go out
  /// concurrently.
  Future<List<NoteEntry>> fetchNotes(String relatedTo, String relatedToId) async {
    final body = await _api.get(ApiEndpoints.notes, query: {
      'related_to': relatedTo,
      'related_to_id': relatedToId,
      'page_size': 100,
    });
    final page = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
    final out = <NoteEntry>[];
    final threaded = <NoteEntry>[];
    for (final row in page.results) {
      final note = noteFromJson(row);
      if (note == null) continue;
      out.add(note);
      // Absent `reply_count` means "unknown", not "none" — fetch rather than
      // silently drop a thread the response simply did not describe.
      final count = _replyCount(row);
      if (count == null || count > 0) threaded.add(note);
    }
    await Future.wait([
      for (final n in threaded)
        fetchReplies(n.id).then((replies) => n.replies
          ..clear()
          ..addAll(replies)),
    ]);
    return out;
  }

  /// One note's replies, oldest-first (the order the API returns them, which is
  /// natural reading order under the parent).
  ///
  /// A failed thread yields an empty list rather than throwing: the whole notes
  /// panel falling back to empty over one bad thread loses far more than the
  /// replies it could not load.
  Future<List<NoteReply>> fetchReplies(String noteId) async {
    try {
      final body = await _api.get(ApiEndpoints.noteReplies(noteId),
          query: {'page_size': 100});
      final page = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      return [for (final row in page.results) replyFromJson(row)];
    } on Object {
      return const [];
    }
  }

  /// The row's `reply_count`, or null when it is missing or unreadable.
  static int? _replyCount(Map<String, dynamic> row) {
    final raw = row['reply_count'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  /// Creates a top-level note; returns the mapped created row (null on shape
  /// surprise — the caller keeps its optimistic entry).
  Future<NoteEntry?> addNote(
      String relatedTo, String relatedToId, String body) async {
    final res = await _api.post(ApiEndpoints.notes, body: {
      'content': body,
      'related_to': relatedTo,
      'related_to_id': relatedToId,
    });
    return res is Map<String, dynamic> ? noteFromJson(res) : null;
  }

  /// `POST /crm/attachments/` (multipart) — attaches one picked file to a note.
  ///
  /// Attachments are a **second call**: the note must exist first, because the
  /// upload points back at its `note_id`. A reply is a note too, so the same
  /// call attaches to either.
  ///
  /// Returns the attachment with its CDN [NoteAttachment.url] filled in, or
  /// null when the response has no usable file link.
  Future<NoteAttachment?> addAttachment(
    String noteId,
    NoteAttachment attachment,
  ) async {
    final path = attachment.localPath;
    if (path == null) return null;

    final form = FormData.fromMap({
      'related_to': 'note',
      'related_to_id': noteId,
      'name': attachment.name,
      'file_upload': await MultipartFile.fromFile(path, filename: attachment.name),
    });
    final res = await _api.postForm(ApiEndpoints.attachments, form);
    if (res is! Map<String, dynamic>) return null;

    final url = _str(res['file']);
    if (url == null) return null;
    return attachment.copyWith(url: url);
  }

  /// Posts a reply under [noteId]; returns the mapped reply.
  Future<NoteReply> addReply(String noteId, String body) async {
    final res =
        await _api.post(ApiEndpoints.noteReplies(noteId), body: {'content': body});
    return replyFromJson(
        res is Map<String, dynamic> ? res : const <String, dynamic>{},
        fallbackBody: body);
  }

  // ── mapping (static so tests can exercise fixtures directly) ──

  /// One API note → [NoteEntry]. A row without a `note_id` returns null.
  static NoteEntry? noteFromJson(Map<String, dynamic> json, {DateTime? now}) {
    final id = _str(json['note_id']);
    if (id == null || id.isEmpty) return null;

    final by = json['created_by'];
    UserDirectory.registerJson(by);
    final type = json['note_type'];
    final typeName = type is Map ? _str(type['name']) : null;
    final attachments = <NoteAttachment>[];
    final rawAtts = json['attachments'];
    if (rawAtts is List) {
      for (final a in rawAtts) {
        if (a is Map) {
          attachments.add(attachmentFromJson(Map<String, dynamic>.from(a)));
        }
      }
    }

    return NoteEntry(
      id: id,
      author: (by is Map ? _str(by['full_name']) : null) ?? 'Unknown',
      time: relativeTime(parseApiDate(json['created_at']), now: now),
      body: _str(json['content']) ?? '',
      via: (typeName == 'Call' || typeName == 'Email') ? typeName : null,
      attachments: attachments,
    );
  }

  /// One API reply → [NoteReply].
  ///
  /// Time comes from `created_at`, so a thread loaded from the server reads
  /// "2d ago" rather than claiming every old reply was just written. A reply
  /// echoed back without one — or mapped straight after posting — is "Just
  /// now", which is true in that case.
  static NoteReply replyFromJson(Map<String, dynamic> json,
      {String? fallbackBody, DateTime? now}) {
    final by = json['created_by'];
    UserDirectory.registerJson(by);
    final content = _str(json['content']);
    final created = parseApiDate(json['created_at']);
    return NoteReply(
      author: (by is Map ? _str(by['full_name']) : null) ?? 'You',
      time: created == null ? 'Just now' : relativeTime(created, now: now),
      body: (content != null && content.isNotEmpty)
          ? content
          : (fallbackBody ?? ''),
    );
  }

  /// One API attachment → [NoteAttachment]; kind inferred from the extension.
  static NoteAttachment attachmentFromJson(Map<String, dynamic> json) {
    final url = _str(json['file']);
    final name = _str(json['name']) ?? _lastSegment(url) ?? 'Attachment';
    final probe = (url != null && url.isNotEmpty) ? url : name;
    return NoteAttachment(
      kind: _isImage(probe) ? 'image' : 'file',
      name: name,
      url: url,
    );
  }

  static const _imageExts = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic',
  };

  static bool _isImage(String path) {
    final clean = path.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return false;
    return _imageExts.contains(clean.substring(dot + 1).toLowerCase());
  }

  static String? _lastSegment(String? url) {
    if (url == null || url.isEmpty) return null;
    final clean = url.split('?').first;
    final slash = clean.lastIndexOf('/');
    final seg = slash < 0 ? clean : clean.substring(slash + 1);
    return seg.isEmpty ? null : seg;
  }
}

String? _str(Object? v) => v is String ? v : null;
