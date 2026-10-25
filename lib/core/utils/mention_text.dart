/// Inline @mention helpers for the notes composer — a port of the webapp's
/// `notes/presentation/lib/mentionText.ts`. Mentions live in the note text as
/// `@<display name>` (the backend stores plain text plus a separate
/// `mentioned_user_ids` list), so the text is the single source of truth: the
/// ids sent on submit are whichever known users still have their `@name` token
/// in the draft.
library;

typedef MentionUser = ({String id, String name});

final _word = RegExp(r'[\p{L}\p{N}_]', unicode: true);

/// Longest name fragment still matched before the suggestion list gives up.
const _maxQuery = 40;

bool _isWordChar(String text, int i) =>
    i >= 0 && i < text.length && _word.hasMatch(text[i]);

/// One run of a tokenized draft: plain text, or a `@name` token for [id].
typedef MentionSegment = ({String text, String? id});

/// Splits [text] into plain runs and `@name` tokens (longest name wins).
List<MentionSegment> tokenizeMentions(String text, List<MentionUser> users) {
  final sorted = users.where((u) => u.name.trim().isNotEmpty).toList()
    ..sort((a, b) => b.name.length.compareTo(a.name.length));
  final out = <MentionSegment>[];
  var plainFrom = 0;
  var i = 0;
  while (i < text.length) {
    if (text[i] == '@' && !_isWordChar(text, i - 1)) {
      MentionUser? hit;
      for (final u in sorted) {
        final end = i + 1 + u.name.length;
        if (text.startsWith(u.name, i + 1) && !_isWordChar(text, end)) {
          hit = u;
          break;
        }
      }
      if (hit != null) {
        if (i > plainFrom) out.add((text: text.substring(plainFrom, i), id: null));
        final end = i + 1 + hit.name.length;
        out.add((text: text.substring(i, end), id: hit.id));
        i = end;
        plainFrom = end;
        continue;
      }
    }
    i += 1;
  }
  if (plainFrom < text.length) out.add((text: text.substring(plainFrom), id: null));
  return out;
}

/// Ids of the users whose `@name` appears in [text], in first-appearance order.
List<String> mentionedIdsIn(String text, List<MentionUser> users) {
  final ids = <String>[];
  for (final s in tokenizeMentions(text, users)) {
    if (s.id != null && !ids.contains(s.id)) ids.add(s.id!);
  }
  return ids;
}

/// The `@query` being typed right before [caret], or null. The `@` must start
/// a word (so `a@b.com` doesn't trigger) and the query can't cross a line
/// break. Once a known name is complete and typing has moved past it, the
/// query is over — unless a longer name still continues it.
({int start, String query})? activeMentionAt(String text, int caret, List<MentionUser> users) {
  if (caret < 0 || caret > text.length) return null;
  final before = text.substring(0, caret);
  final at = before.lastIndexOf('@');
  if (at < 0 || _isWordChar(text, at - 1)) return null;
  final query = before.substring(at + 1);
  if (query.length > _maxQuery || query.contains('\n') || query.contains('@') || query.startsWith(' ')) {
    return null;
  }
  final q = query.toLowerCase();
  final completed = users.any((u) {
    final l = u.name.toLowerCase();
    return q.length > l.length && q.startsWith(l) && !_isWordChar(q, l.length);
  });
  if (completed && !users.any((u) => u.name.toLowerCase().startsWith(q))) return null;
  return (start: at, query: query);
}

/// Users whose name matches [query] — name-start matches first.
List<MentionUser> filterMentionCandidates(List<MentionUser> users, String query, {int limit = 8}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return users.take(limit).toList();
  final starts = <MentionUser>[];
  final contains = <MentionUser>[];
  for (final u in users) {
    final label = u.name.toLowerCase();
    if (label.startsWith(q) || label.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) {
      starts.add(u);
    } else if (label.contains(q)) {
      contains.add(u);
    }
  }
  return [...starts, ...contains].take(limit).toList();
}

/// Replaces the `@query` at [start, caret) with `@name ` — returns the new
/// text and caret.
({String text, int caret}) insertMention(String text, int start, int caret, String name) {
  final token = '@$name ';
  final rest = text.substring(caret);
  final next = text.substring(0, start) + token + (rest.startsWith(' ') ? rest.substring(1) : rest);
  return (text: next, caret: start + token.length);
}

/// Inserts `@name ` at [caret] (from the Mention picker), padding with a space
/// when the caret sits against a word.
({String text, int caret}) appendMention(String text, int caret, String name) {
  final pos = caret.clamp(0, text.length);
  final lead = pos > 0 && !RegExp(r'\s').hasMatch(text[pos - 1]) ? ' ' : '';
  final token = '$lead@$name ';
  return (text: text.substring(0, pos) + token + text.substring(pos), caret: pos + token.length);
}

/// Removes every `@name` token for [id] (and one trailing space) from [text].
String removeMention(String text, String id, List<MentionUser> users) {
  final segs = tokenizeMentions(text, users);
  final b = StringBuffer();
  for (var i = 0; i < segs.length; i++) {
    final s = segs[i];
    if (s.id == id) continue;
    final prev = i > 0 ? segs[i - 1] : null;
    if (s.id == null && prev?.id == id && s.text.startsWith(' ')) {
      b.write(s.text.substring(1));
    } else {
      b.write(s.text);
    }
  }
  return b.toString();
}
