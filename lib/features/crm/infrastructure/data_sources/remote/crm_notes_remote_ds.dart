import '../../../../../core/models/note.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/user_directory.dart';

/// Remote notes (`/crm/notes/`) for any CRM record (`lead` / `customer` /
/// `task` — follow-ups pass `task` too). HTTP + JSON → [NoteEntry] mapping
/// only; the notes notifier owns state and optimism.
class CrmNotesRemoteDataSource {
  const CrmNotesRemoteDataSource(this._api);

  final ApiService _api;

  /// Top-level notes for one record, newest-first. Replies load lazily (the
  /// mobile panel shows threads without hydrating them), so `replies` is
  /// always empty here.
  Future<List<NoteEntry>> fetchNotes(String relatedTo, String relatedToId) async {
    final body = await _api.get(ApiEndpoints.notes, query: {
      'related_to': relatedTo,
      'related_to_id': relatedToId,
      'page_size': 100,
    });
    final page = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
    final out = <NoteEntry>[];
    for (final row in page.results) {
      final note = noteFromJson(row);
      if (note != null) out.add(note);
    }
    return out;
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

  /// One API reply → [NoteReply]. Time renders as "Just now" because replies
  /// are only mapped straight after posting.
  static NoteReply replyFromJson(Map<String, dynamic> json,
      {String? fallbackBody}) {
    final by = json['created_by'];
    final content = _str(json['content']);
    return NoteReply(
      author: (by is Map ? _str(by['full_name']) : null) ?? 'You',
      time: 'Just now',
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
