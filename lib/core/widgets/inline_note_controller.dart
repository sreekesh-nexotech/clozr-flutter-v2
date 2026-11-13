import 'package:flutter/material.dart';

import '../models/note.dart';

/// A text controller whose text can carry attachments *inside* it, at the
/// caret, as chips — the webapp's note editor.
///
/// Each attachment is one placeholder character ([kAttObject]) in [text]; the
/// i-th placeholder belongs to `attachments[i]`. Text, caret and selection stay
/// ordinary one-character-per-glyph, so typing, deleting and mentions behave as
/// in any field, and removing the placeholder (Backspace, or the chip's ×)
/// removes the attachment.
///
/// [encode] turns the draft into the text the API stores, each placeholder
/// becoming the attachment's `[[att:<id>]]` marker.
class InlineNoteController extends TextEditingController {
  InlineNoteController({super.text}) {
    _prev = text;
    addListener(_sync);
  }

  /// Draws one attachment's chip. Set by the owning widget.
  Widget Function(NoteAttachment attachment, int index)? chipBuilder;

  /// The attachments in the order their placeholders appear in [text].
  final List<NoteAttachment> attachments = [];

  String _prev = '';
  bool _internal = false;

  static int _count(String s) => kAttObject.allMatches(s).length;

  /// Puts [a] into the text at the caret, replacing any selected text.
  void insertAttachment(NoteAttachment a) {
    final t = text;
    final sel = selection;
    final start = sel.isValid ? sel.start.clamp(0, t.length) : t.length;
    final end = sel.isValid ? sel.end.clamp(start, t.length) : t.length;
    final before = _count(t.substring(0, start));
    final replaced = _count(t.substring(start, end));
    attachments.removeRange(before, before + replaced);
    attachments.insert(before, a);
    _replaceText(t.replaceRange(start, end, kAttObject), start + 1);
  }

  /// Removes the i-th attachment and its placeholder.
  void removeAttachmentAt(int index) {
    if (index < 0 || index >= attachments.length) return;
    final t = text;
    var seen = -1;
    var at = -1;
    for (var i = 0; i < t.length; i++) {
      if (t[i] == kAttObject && ++seen == index) {
        at = i;
        break;
      }
    }
    attachments.removeAt(index);
    if (at < 0) {
      notifyListeners();
      return;
    }
    final caret = selection.isValid ? selection.baseOffset : at;
    _replaceText(
        t.replaceRange(at, at + 1, ''), caret > at ? caret - 1 : caret);
  }

  void _replaceText(String next, int caret) {
    _internal = true;
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret.clamp(0, next.length)),
    );
    _internal = false;
    _prev = next;
  }

  /// Keeps [attachments] in step when the user deletes, cuts or pastes over a
  /// placeholder: whichever ones left the text leave the list.
  void _sync() {
    if (_internal) return;
    final now = text;
    if (now == _prev) return;
    final old = _prev;
    // The edit is the stretch between the shared head and the shared tail.
    var head = 0;
    final shortest = old.length < now.length ? old.length : now.length;
    while (head < shortest && old[head] == now[head]) {
      head++;
    }
    var tail = 0;
    while (tail < shortest - head &&
        old[old.length - 1 - tail] == now[now.length - 1 - tail]) {
      tail++;
    }
    final removed = old.substring(head, old.length - tail);
    final added = now.substring(head, now.length - tail);
    if (removed.contains(kAttObject)) {
      final first = _count(old.substring(0, head));
      attachments.removeRange(first, first + _count(removed));
    }
    // A placeholder that arrived by paste has no attachment behind it.
    if (added.contains(kAttObject)) {
      _prev = old; // let the strip below read as one edit
      final cleaned = now.replaceRange(
          head, now.length - tail, added.replaceAll(kAttObject, ''));
      final caret = (selection.baseOffset -
              (added.length - added.replaceAll(kAttObject, '').length))
          .clamp(0, cleaned.length);
      _replaceText(cleaned, caret);
      return;
    }
    _prev = now;
  }

  /// The text as the API stores it: each placeholder as its `[[att:<id>]]`.
  String encode() {
    final b = StringBuffer();
    var i = 0;
    for (final ch in text.split('')) {
      if (ch == kAttObject) {
        final id = i < attachments.length ? attachments[i].markerId : null;
        i++;
        if (id != null) b.write(attMarker(id));
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }

  /// Loads a stored note: `[[att:<id>]]` markers become placeholders backed by
  /// the note's own [known] attachments (a marker with no match is dropped).
  void load(String body, List<NoteAttachment> known) {
    final b = StringBuffer();
    final list = <NoteAttachment>[];
    for (final piece in splitNoteContent(body)) {
      if (piece.text != null) {
        b.write(piece.text);
        continue;
      }
      final a = known.where((k) => k.markerId == piece.attId).firstOrNull;
      if (a == null) continue;
      list.add(a);
      b.write(kAttObject);
    }
    attachments
      ..clear()
      ..addAll(list);
    _replaceText(b.toString(), b.length);
  }

  @override
  void clear() {
    attachments.clear();
    _internal = true;
    super.clear();
    _internal = false;
    _prev = '';
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!text.contains(kAttObject) || chipBuilder == null) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    final spans = <InlineSpan>[];
    var i = 0;
    final run = StringBuffer();
    void flush() {
      if (run.isEmpty) return;
      spans.add(TextSpan(text: run.toString(), style: style));
      run.clear();
    }

    for (final ch in text.split('')) {
      if (ch != kAttObject) {
        run.write(ch);
        continue;
      }
      flush();
      final index = i++;
      if (index >= attachments.length) {
        spans.add(TextSpan(text: kAttObject, style: style));
        continue;
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: chipBuilder!(attachments[index], index),
      ));
    }
    flush();
    return TextSpan(style: style, children: spans);
  }
}
