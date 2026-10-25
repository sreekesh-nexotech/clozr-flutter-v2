/// What a CRM notification's text says about the record it is about.
///
/// The row carries no source-object id (see `_targetFor` in the remote data
/// source), so the record is recovered from the text the server writes:
/// * lead events name the lead — `…assigned to lead: Ravi Kumar`,
///   `New note "Note" added to lead "Ravi Kumar".`, `Lead "Ravi Kumar" status
///   changed to Won.`;
/// * quote events name the quote number — `Discount on quote QTN-00037 was
///   approved.`;
/// * a mention quotes the note — `Ashish Nexotech mentioned you: <note>`.
///
/// The screen resolves the hint against the API and falls back to the
/// module list when nothing matches, as before.
sealed class NotificationLink {
  const NotificationLink();
}

/// A lead, by its exact name.
class LeadByName extends NotificationLink {
  const LeadByName(this.name);
  final String name;
}

/// A quote, by its number (the quote screen opens by number).
class QuoteByNumber extends NotificationLink {
  const QuoteByNumber(this.number);
  final String number;
}

/// The note a mention quotes, by its text.
class NoteByContent extends NotificationLink {
  const NoteByContent(this.content);
  final String content;
}

final _quoteNo = RegExp(r'\bQTN-\d+(?:-R\d+)?\b');
final _leadQuoted = RegExp(r'\blead\s*"([^"]+)"', caseSensitive: false);
final _leadAfterColon = RegExp(r'\blead:\s*(.+?)\s*\.?$', caseSensitive: false);
final _mention = RegExp(r'mentioned you:\s*(.+)$', dotAll: true);

/// The record hint for a notification of [type] with [text]; null when the
/// text names nothing usable.
NotificationLink? notificationLinkFor(String type, String text) {
  final t = type.toLowerCase();
  final s = text.trim();
  if (t.contains('mention')) {
    final m = _mention.firstMatch(s);
    final body = m?.group(1)?.trim() ?? '';
    return body.isEmpty ? null : NoteByContent(body);
  }
  if (t.startsWith('quot')) {
    final m = _quoteNo.firstMatch(s);
    return m == null ? null : QuoteByNumber(m.group(0)!);
  }
  if (t.startsWith('lead')) {
    final quoted = _leadQuoted.allMatches(s).toList();
    if (quoted.isNotEmpty) return LeadByName(quoted.last.group(1)!.trim());
    final m = _leadAfterColon.firstMatch(s);
    final name = m?.group(1)?.trim() ?? '';
    return name.isEmpty ? null : LeadByName(name);
  }
  return null;
}

/// A note row's `source` → (kind, id) for routing, e.g. ('lead', '<uuid>').
(String, String)? noteSourceOf(Map<String, dynamic> note) {
  final src = note['source'];
  if (src is! Map) return null;
  final kind = '${src['kind'] ?? src['model'] ?? ''}'.toLowerCase();
  final id = '${src['id'] ?? ''}';
  if (kind.isEmpty || id.isEmpty) return null;
  return (kind, id);
}

/// Whether a note's stored content is the text a mention quoted. The
/// notification text is the content as typed; the stored copy may carry
/// mention markup or surrounding whitespace, so compare loosely.
bool noteMatchesMention(String content, String quoted) {
  String norm(String v) => v.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  final a = norm(content);
  final b = norm(quoted);
  return a.isNotEmpty && (a == b || a.endsWith(b) || b.endsWith(a));
}
