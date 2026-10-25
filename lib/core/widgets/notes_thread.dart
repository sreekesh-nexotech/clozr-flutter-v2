import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import '../../features/shell/application/providers/shell_providers.dart';
import '../models/note.dart';
import '../utils/attachment_link.dart';
import '../utils/mention_text.dart';
import 'attachment_preview.dart';
import 'app_bottom_sheet.dart';

/// The shared Notes section used on every detail page (#13).
///
/// Renders the "Notes" card: a composer (avatar + input + attach + send) and a
/// thread where each note carries an optional source pill, attachment chips,
/// nested replies, and an inline reply composer. The host owns the [notes]
/// list and the mutation callbacks; this widget owns only the transient
/// composer/reply/attachment draft state.
class NotesThread extends ConsumerStatefulWidget {
  const NotesThread({
    super.key,
    required this.notes,
    required this.onAddNote,
    required this.onAddReply,
    required this.author,
    this.onTogglePin,
    this.noteTypes = const [],
    this.mentionables = const [],
    this.onAddTypedNote,
    this.currentUserId,
    this.onEditNote,
    this.onDeleteNote,
    this.readOnly = false,
    this.webappToolbar = false,
  });

  /// Shows the webapp composer's toolbar (Tag · Mention · Insert) — the CRM
  /// records' notes. Insert is always there; Tag and Mention appear once the
  /// org's tags / mentionable users have loaded.
  final bool webappToolbar;

  /// The org's note types for the composer's "Tag" picker. Empty hides it.
  final List<NoteTypeOption> noteTypes;

  /// People who can be @mentioned. Empty hides the mention picker.
  final List<({String id, String name})> mentionables;

  /// Used instead of [onAddNote] when set: also carries the chosen tag and
  /// the users still @mentioned in the text (webapp `mentionedIdsIn`).
  final void Function(String body, List<NoteAttachment> attachments, String? noteTypeId,
      String? noteTypeName, List<String> mentionedUserIds)? onAddTypedNote;

  /// The signed-in user — only a note's author may pin, edit or delete it.
  final String? currentUserId;

  /// Edits note [id]; returns the server's error or null.
  final Future<String?> Function(String id, String body)? onEditNote;

  /// Deletes note [id]; returns the server's error or null.
  final Future<String?> Function(String id)? onDeleteNote;

  /// A frozen record (a converted lead): no composer and no Reply.
  final bool readOnly;

  final List<NoteEntry> notes;
  /// Who the composer is writing as — supply from `noteAuthorProvider`.
  final NoteAuthor author;

  /// Called when the user posts a new note with any pending attachments.
  final void Function(String body, List<NoteAttachment> attachments) onAddNote;

  /// Called when the user replies to note [noteId].
  final void Function(String noteId, String body) onAddReply;

  /// Called when the user pins or unpins note [noteId].
  ///
  /// Optional, and the pin control is hidden entirely when it is null — the
  /// thread is shared by every module's detail screen, and a pin that does
  /// nothing is worse than no pin at all. Ordering is the host's job: this
  /// widget renders [notes] in the order it is handed them.
  final void Function(String noteId)? onTogglePin;

  @override
  ConsumerState<NotesThread> createState() => NotesThreadState();
}

class NotesThreadState extends ConsumerState<NotesThread> {
  final _noteCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();
  final _noteFocus = FocusNode();
  final List<NoteAttachment> _pending = [];
  String? _openReplyFor;

  /// The composer's tag — "No tag" (null) until picked, reset after posting.
  NoteTypeOption? _noteType;

  /// Focuses the composer — used by the "add note" affordance in the sticky bar.
  void focusComposer() => _noteFocus.requestFocus();

  /// Webapp composer toolbar (Tag · Mention · Insert) — the CRM records, or
  /// any host that wires the webapp's tags or mentions. Other hosts keep the
  /// paperclip inside the field.
  bool get _toolbar => widget.webappToolbar || widget.noteTypes.isNotEmpty || widget.mentionables.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Inline @mentions: the suggestion list follows the text and the caret.
    _noteCtrl.addListener(_onDraftChanged);
    _noteFocus.addListener(_onDraftChanged);
  }

  /// The `@query` being typed in the composer, or null.
  ({int start, String query})? _activeMention;
  int _mentionCount = 0;

  void _onDraftChanged() {
    final sel = _noteCtrl.selection;
    final next = widget.mentionables.isEmpty || !_noteFocus.hasFocus || !sel.isValid || !sel.isCollapsed
        ? null
        : activeMentionAt(_noteCtrl.text, sel.baseOffset, widget.mentionables);
    // The Mention chip's "N mentioned" follows the text too.
    final count = widget.mentionables.isEmpty ? 0 : _mentionedIn(_noteCtrl.text).length;
    if (next == _activeMention && count == _mentionCount) return;
    if (mounted) {
      setState(() {
        _activeMention = next;
        _mentionCount = count;
      });
    }
  }

  void _setDraft(String text, int caret) {
    _noteCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret.clamp(0, text.length)),
    );
  }

  /// Picks [user] from the inline suggestion list: `@query` → `@Name `.
  void _pickInlineMention(({String id, String name}) user) {
    final m = _activeMention;
    if (m == null) return;
    final r = insertMention(_noteCtrl.text, m.start, _noteCtrl.selection.baseOffset, user.name);
    _setDraft(r.text, r.caret);
    _noteFocus.requestFocus();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _replyCtrl.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _send() {
    final body = _noteCtrl.text.trim();
    if (body.isEmpty && _pending.isEmpty) return;
    final typed = widget.onAddTypedNote;
    if (typed != null) {
      typed(body, List.of(_pending), _noteType?.id, _noteType?.name, _mentionedIn(body));
      ref.read(toastProvider.notifier).show('Note added');
    } else {
      widget.onAddNote(body, List.of(_pending));
    }
    _noteCtrl.clear();
    setState(() {
      _pending.clear();
      _noteType = null;
    });
    FocusScope.of(context).unfocus();
  }

  /// Users whose `@Name` token is still in [text] (webapp `mentionedIdsIn`).
  List<String> _mentionedIn(String text) => mentionedIdsIn(text, widget.mentionables);

  /// The tag's own colour (the server's hex), or the muted text colour.
  static Color _tagColor(String hex) {
    final h = hex.replaceFirst('#', '').trim();
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return h.length == 6 && v != null ? Color(v) : AppColors.textMuted;
  }

  static Widget _dot(Color c) => Container(
        width: 8.r,
        height: 8.r,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  /// Webapp `NoteTypePicker`: "No tag" plus the org's tags, each with its dot.
  Future<void> _pickNoteType() async {
    final picked = await showClozrSheet<NoteTypeOption>(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SheetHeader(title: 'Tag'),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              ListTile(
                leading: _dot(const Color(0xFF9AA0A6)),
                minLeadingWidth: 8.w,
                title: const Text('No tag'),
                trailing: _noteType == null ? Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.navy) : null,
                onTap: () => Navigator.of(ctx).pop((id: '', name: '', color: '')),
              ),
              for (final t in widget.noteTypes)
                ListTile(
                  leading: _dot(_tagColor(t.color)),
                  minLeadingWidth: 8.w,
                  title: Text(t.name),
                  trailing: _noteType?.id == t.id ? Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.navy) : null,
                  onTap: () => Navigator.of(ctx).pop(t),
                ),
            ]),
          ),
          SizedBox(height: 8.h),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _noteType = picked.id.isEmpty ? null : picked);
  }

  /// Webapp `MentionPicker`: a multi-select list. Ticking writes `@Name` into
  /// the text at the caret, unticking strips that user's tokens — so the
  /// picker and typed mentions never disagree.
  Future<void> _pickMention() async {
    final users = widget.mentionables;
    await showClozrSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final on = _mentionedIn(_noteCtrl.text);
          return SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SheetHeader(title: 'Mention'),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final u in users)
                    CheckboxListTile(
                      value: on.contains(u.id),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.navy,
                      title: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onChanged: (_) {
                        _toggleMention(u, on.contains(u.id));
                        setSheet(() {});
                      },
                    ),
                ]),
              ),
              SizedBox(height: 8.h),
            ]),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  void _toggleMention(({String id, String name}) user, bool wasOn) {
    final text = _noteCtrl.text;
    final sel = _noteCtrl.selection;
    final caret = sel.isValid ? sel.baseOffset : text.length;
    if (wasOn) {
      final next = removeMention(text, user.id, widget.mentionables);
      _setDraft(next, caret.clamp(0, next.length));
    } else {
      final r = appendMention(text, caret, user.name);
      _setDraft(r.text, r.caret);
    }
  }

  /// Webapp "Insert": pick one file, then name it — the name is what the note
  /// shows as the attachment's link text.
  Future<void> _insertFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        withData: false,
        allowedExtensions: _allowedExtensions,
      );
    } on Object catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).showError('Could not open the file picker: $e');
      return;
    }
    final f = result?.files.firstOrNull;
    final path = f?.path;
    if (f == null || path == null || !mounted) return; // cancelled
    final kind = _kindOf(f.extension);
    if (f.size > (kind == 'image' ? _imageSizeLimit : _fileSizeLimit)) {
      ref.read(toastProvider.notifier)
          .showError('${f.name} is too large — max ${kind == 'image' ? '5 MB' : '10 MB'}');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameAttachmentDialog(initial: f.name),
    );
    if (name == null || name.isEmpty || !mounted) return; // cancelled or blank
    setState(() => _pending.add(NoteAttachment(
          name: name,
          kind: kind,
          size: _formatBytes(f.size),
          localPath: path,
        )));
  }

  /// Author-only actions (webapp `NoteCard`): Pin/Unpin, Edit, Delete.
  Future<void> _noteActions(NoteEntry n) async {
    final mine = widget.currentUserId != null && n.authorId == widget.currentUserId;
    if (!mine || widget.readOnly && widget.onEditNote == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.onTogglePin != null)
            ListTile(
              leading: Icon(n.pinned ? PhosphorIconsRegular.pushPinSlash : PhosphorIconsRegular.pushPin),
              title: Text(n.pinned ? 'Unpin' : 'Pin'),
              onTap: () => Navigator.of(ctx).pop('pin'),
            ),
          if (widget.onEditNote != null)
            ListTile(
              leading: const Icon(PhosphorIconsRegular.pencilSimple),
              title: const Text('Edit'),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
          if (widget.onDeleteNote != null)
            ListTile(
              leading: const Icon(PhosphorIconsRegular.trash, color: AppColors.error),
              title: const Text('Delete', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    final toast = ref.read(toastProvider.notifier);
    switch (action) {
      case 'pin':
        widget.onTogglePin!(n.id);
        toast.show(n.pinned ? 'Unpinned' : 'Pinned');
      case 'edit':
        // The dialog owns its controller: disposing one here, while the
        // dialog is still animating out, crashed the screen.
        final body = await showDialog<String>(
          context: context,
          builder: (ctx) => _EditNoteDialog(initial: n.body),
        );
        if (body == null || body.isEmpty || body == n.body || !mounted) return;
        final err = await widget.onEditNote!(n.id, body);
        err == null ? toast.show('Note updated') : toast.showError(err);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete note?'),
            content: const Text('This permanently removes the note and its replies.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Delete', style: TextStyle(color: AppColors.error))),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        final err = await widget.onDeleteNote!(n.id);
        err == null ? toast.show('Note deleted') : toast.showError(err);
    }
  }

  void _sendReply(String noteId) {
    final body = _replyCtrl.text.trim();
    if (body.isEmpty) return;
    widget.onAddReply(noteId, body);
    if (widget.onAddTypedNote != null) ref.read(toastProvider.notifier).show('Reply posted');
    _replyCtrl.clear();
    setState(() => _openReplyFor = null);
    FocusScope.of(context).unfocus();
  }

  void _pickAttachment() {
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Attach to note'),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
            child: Column(
              children: [
                _attachOption(ctx, PhosphorIconsRegular.image, 'Photo', () {
                  _pickFrom(FileType.image);
                }),
                _attachOption(ctx, PhosphorIconsRegular.paperclip, 'File', () {
                  _pickFrom(FileType.custom);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The file types the notes API accepts (rulebook §11.6): images, PDF, Excel
  /// and Markdown. Constraining the picker means a rejected upload is something
  /// the user can't stumble into.
  static const _allowedExtensions = [
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic',
    'pdf', 'xls', 'xlsx', 'csv', 'md',
  ];

  /// Same caps as the WhatsApp composer (`whatsapp.md` §4.5), kept consistent
  /// here so a "too large" file behaves the same everywhere in the app rather
  /// than queuing silently and only failing — invisibly — once the note is
  /// posted and the upload hits the send timeout.
  static const _imageSizeLimit = 5 * 1024 * 1024;
  static const _fileSizeLimit = 10 * 1024 * 1024;

  /// Picks real files off the device and queues them for upload.
  ///
  /// Multi-select: the composer already renders a chip per pending file, and
  /// the upload loop posts them one at a time.
  Future<void> _pickFrom(FileType type) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: type,
        allowMultiple: true,
        withData: false, // paths only — a large file should not sit in memory
        allowedExtensions: type == FileType.custom ? _allowedExtensions : null,
      );
    } on Object catch (e) {
      // The picker is a native plugin: on a hot restart after it was added, it
      // is not registered yet and every call throws. Silence here reads as "the
      // button does nothing", so say what actually happened.
      if (!mounted) return;
      // The app toast, not a SnackBar: this composer is often inside a
      // root-navigator bottom sheet, where a SnackBar renders under the sheet,
      // and `ScaffoldMessenger.maybeOf` drops the message outright when there is
      // no messenger in scope. The toast is mounted above the navigator and
      // clears the keyboard, which is always up while a note is being written.
      ref.read(toastProvider.notifier).showError('Could not open the file picker: $e');
      return;
    }
    final picked = result;
    if (picked == null || !mounted) return; // cancelled

    final tooLarge = <String>[];
    setState(() {
      for (final f in picked.files) {
        final path = f.path;
        if (path == null) continue;
        final kind = _kindOf(f.extension);
        final limit = kind == 'image' ? _imageSizeLimit : _fileSizeLimit;
        if (f.size > limit) {
          tooLarge.add(f.name);
          continue;
        }
        _pending.add(NoteAttachment(
          name: f.name,
          kind: kind,
          size: _formatBytes(f.size),
          localPath: path,
        ));
      }
    });
    // Said now, at pick time, rather than discovered after the note has
    // already posted and the upload silently times out — which is what
    // happened before this check existed.
    if (tooLarge.isNotEmpty && mounted) {
      final limitLabel = type == FileType.image ? '5 MB' : '10 MB';
      ref.read(toastProvider.notifier).showError(tooLarge.length == 1
          ? '${tooLarge.first} is too large — max $limitLabel'
          : '${tooLarge.length} files are too large — max $limitLabel');
    }
  }

  static String _kindOf(String? extension) {
    const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'};
    return imageExts.contains((extension ?? '').toLowerCase()) ? 'image' : 'file';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  Widget _attachOption(BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(ctx).pop();
        onTap();
      },
      child: Container(
        height: 52.h,
        padding: EdgeInsets.symmetric(horizontal: 6.w),
        child: Row(
          children: [
            Icon(icon, size: 20.sp, color: AppColors.navy),
            SizedBox(width: 14.w),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Manrope',
                    fontVariations: const [FontVariation('wght', 600.0)],
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 14.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(color: const Color(0xFF101828).withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: const Color(0xFFEEF0F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Notes',
                  style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 700.0)], fontSize: 15.sp, fontWeight: FontWeight.w700, color: const Color(0xFF14151A))),
              SizedBox(width: 8.w),
              Text('${widget.notes.length}',
                  style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 600.0)], fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
          ),
          SizedBox(height: 13.h),
          if (!widget.readOnly) ...[
            _composer(),
            if (_activeMention != null) _mentionSuggestions(),
          ],
          if (_pending.isNotEmpty) _pendingChips(),
          if (!widget.readOnly && _toolbar) _composerExtras(),
          SizedBox(height: 2.h),
          for (final n in widget.notes) _noteRow(n),
        ],
      ),
    );
  }

  /// The webapp composer's toolbar: Tag (the picked tag in its colour),
  /// Mention ("N mentioned" once anyone is), and Insert.
  Widget _composerExtras() {
    final mentioned = _mentionCount;
    final tag = _noteType;
    final tagColor = tag == null ? null : _tagColor(tag.color);
    Widget chip({
      required VoidCallback onTap,
      required List<Widget> children,
      Color border = const Color(0xFFE6E7EA),
      Color fill = AppColors.white,
    }) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(9.r),
              border: Border.all(color: border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        );
    TextStyle label(Color c) =>
        TextStyle(fontFamily: 'Manrope', fontSize: 12.5.sp, fontWeight: FontWeight.w600, color: c);
    final muted = AppColors.textMuted;
    return Padding(
      padding: EdgeInsets.only(top: 10.h, left: 44.w),
      child: Wrap(spacing: 8.w, runSpacing: 8.h, children: [
        if (widget.noteTypes.isNotEmpty)
          chip(
            onTap: _pickNoteType,
            border: tagColor ?? const Color(0xFFE6E7EA),
            children: [
              if (tagColor != null) ...[_dot(tagColor), SizedBox(width: 6.w)],
              Text(tag?.name ?? 'Tag', style: label(tagColor ?? muted)),
              SizedBox(width: 4.w),
              Icon(PhosphorIconsRegular.caretDown, size: 12.sp, color: tagColor ?? muted),
            ],
          ),
        if (widget.mentionables.isNotEmpty)
          chip(onTap: _pickMention, children: [
            Icon(PhosphorIconsRegular.at, size: 14.sp, color: muted),
            SizedBox(width: 5.w),
            Text(mentioned > 0 ? '$mentioned mentioned' : 'Mention', style: label(muted)),
            SizedBox(width: 4.w),
            Icon(PhosphorIconsRegular.caretDown, size: 12.sp, color: muted),
          ]),
        chip(onTap: _insertFile, fill: const Color(0xFFF1F1F1), children: [
          Icon(PhosphorIconsRegular.paperclip, size: 14.sp, color: muted),
          SizedBox(width: 5.w),
          Text('Insert', style: label(muted)),
        ]),
      ]),
    );
  }

  /// Webapp `MentionTextarea`'s popup: who matches the `@query` being typed.
  Widget _mentionSuggestions() {
    final hits = filterMentionCandidates(widget.mentionables, _activeMention!.query);
    if (hits.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(top: 6.h, left: 44.w),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFECECEC)),
        boxShadow: [BoxShadow(color: const Color(0xFF101828).withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final u in hits)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickInlineMention(u),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              child: Row(children: [
                _avatar(_initialsOf(u.name), AppColors.navy, 24),
                SizedBox(width: 9.w),
                Expanded(
                  child: Text(u.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Manrope', fontSize: 13.5.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
  }

  Widget _composer() {
    return Row(
      children: [
        _avatar(widget.author.initials, widget.author.color, 34),
        SizedBox(width: 10.w),
        Expanded(
          child: Container(
            height: 46.h,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: const Color(0xFFE6E7EA)),
            ),
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteCtrl,
                    focusNode: _noteFocus,
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                    style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 400.0)], fontSize: 14.sp, color: AppColors.textBody),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Add a note…',
                      hintStyle: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 400.0)], fontSize: 14.sp, color: AppColors.textPlaceholder),
                    ),
                  ),
                ),
                if (!_toolbar)
                  GestureDetector(
                    onTap: _pickAttachment,
                    child: Icon(PhosphorIconsRegular.paperclip, size: 19.sp, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: 10.w),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 46.w,
            height: 46.h,
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
            child: Icon(PhosphorIconsFill.paperPlaneRight, size: 18.sp, color: AppColors.white),
          ),
        ),
      ],
    );
  }

  Widget _pendingChips() {
    return Padding(
      padding: EdgeInsets.only(top: 10.h, left: 44.w),
      child: Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        children: [
          for (int i = 0; i < _pending.length; i++)
            _attachmentChip(_pending[i], onRemove: () => setState(() => _pending.removeAt(i))),
        ],
      ),
    );
  }

  Widget _noteRow(NoteEntry n) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _noteActions(n),
      child: Container(
      padding: EdgeInsets.symmetric(vertical: 13.h),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(n.initials, n.avatarColor ?? AppColors.navy, 30),
          SizedBox(width: 11.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8.w,
                  runSpacing: 4.h,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(n.author,
                        style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 700.0)], fontSize: 13.5.sp, fontWeight: FontWeight.w700, color: const Color(0xFF14151A))),
                    if (n.via != null) _viaPill(n.via!)
                    else if (n.noteType != null && n.noteType!.isNotEmpty) _viaPill(n.noteType!),
                    if (n.pinned) _pinnedPill(),
                    Text(n.time, style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 500.0)], fontSize: 11.sp, fontWeight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                ),
                if (n.body.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Text(n.body,
                        style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 400.0)], fontSize: 14.sp, height: 1.55, color: const Color(0xFF363636))),
                  ),
                if (n.attachments.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 9.h),
                    child: Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [for (final a in n.attachments) _attachmentChip(a)],
                    ),
                  ),
                for (final r in n.replies) _replyRow(r),
                if (_openReplyFor == n.id) _replyComposer(n.id),
                if (!widget.readOnly) GestureDetector(
                  onTap: () => setState(() => _openReplyFor = _openReplyFor == n.id ? null : n.id),
                  child: Padding(
                    padding: EdgeInsets.only(top: 9.h),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.arrowBendDownRight, size: 12.sp, color: const Color(0xFF6B6B6B)),
                        SizedBox(width: 5.w),
                        Text(
                          _openReplyFor == n.id
                              ? 'Cancel'
                              : (n.replies.isEmpty ? 'Reply' : 'Reply (${n.replies.length})'),
                          style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 600.0)], fontSize: 12.5.sp, fontWeight: FontWeight.w600, color: const Color(0xFF6B6B6B)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.onTogglePin != null &&
              (widget.currentUserId == null || n.authorId == widget.currentUserId))
            _pinButton(n),
        ],
      ),
      ),
    );
  }

  /// Tap target for pinning. Filled and navy while pinned, hairline outline
  /// while not, so the current state reads without a legend.
  Widget _pinButton(NoteEntry n) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTogglePin!(n.id);
        if (widget.onAddTypedNote != null) {
          ref.read(toastProvider.notifier).show(n.pinned ? 'Unpinned' : 'Pinned');
        }
      },
      child: Padding(
        padding: EdgeInsets.only(left: 6.w, top: 2.h),
        child: Icon(
          n.pinned ? PhosphorIconsFill.pushPin : PhosphorIconsRegular.pushPin,
          size: 16.sp,
          color: n.pinned ? AppColors.navy : AppColors.textPlaceholder,
        ),
      ),
    );
  }

  /// "Pinned" marker beside the byline, so the reason a note leads the thread
  /// is stated rather than inferred from its position.
  Widget _pinnedPill() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: AppColors.navy.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text('Pinned',
          style: TextStyle(
              fontFamily: 'Manrope',
              fontVariations: const [FontVariation('wght', 700.0)],
              fontSize: 10.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.navy)),
    );
  }

  Widget _replyRow(NoteReply r) {
    return Container(
      margin: EdgeInsets.only(top: 9.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(color: const Color(0xFFF6F8FB), borderRadius: BorderRadius.circular(12.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(r.initials, r.avatarColor ?? AppColors.navy, 24),
          SizedBox(width: 9.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7.w,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(r.author, style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 700.0)], fontSize: 12.5.sp, fontWeight: FontWeight.w700, color: const Color(0xFF14151A))),
                    Text(r.time, style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 500.0)], fontSize: 10.5.sp, fontWeight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(top: 3.h),
                  child: Text(r.body, style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 400.0)], fontSize: 13.sp, height: 1.5, color: const Color(0xFF444444))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyComposer(String noteId) {
    return Padding(
      padding: EdgeInsets.only(top: 10.h),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40.h,
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: const Color(0xFFE6E7EA)),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: _replyCtrl,
                autofocus: true,
                onSubmitted: (_) => _sendReply(noteId),
                textInputAction: TextInputAction.send,
                style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 400.0)], fontSize: 13.sp, color: AppColors.textBody),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Write a reply…',
                  hintStyle: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 400.0)], fontSize: 13.sp, color: AppColors.textPlaceholder),
                ),
              ),
            ),
          ),
          SizedBox(width: 9.w),
          GestureDetector(
            onTap: () => _sendReply(noteId),
            child: Container(
              width: 40.w,
              height: 40.h,
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(10.r)),
              child: Icon(PhosphorIconsFill.paperPlaneRight, size: 15.sp, color: AppColors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Hands a stored attachment to the OS viewer.
  ///
  /// A chip with no hosted link is not silent: a file that has only been picked
  /// lives on the device until the note is posted, and a tap that appears to do
  /// nothing reads as a broken attachment rather than one that has not been
  /// sent yet.
  Future<void> _openAttachment(NoteAttachment a) async {
    if (a.failed) {
      ref.read(toastProvider.notifier).showError(
          "This file didn't upload — it may be too large, or the connection dropped. Remove it and try attaching it again.");
      return;
    }
    final url = a.url;
    // An image previews in-app — including one only just picked, which is read
    // from disk. Waiting until it is posted to see what you attached was the
    // whole complaint.
    if (a.isImage && attachmentImage(a) != null) {
      await showAttachmentPreview(context, a,
          onOpenExternally: () => _launch(url ?? ''));
      return;
    }
    if (url == null || url.isEmpty) {
      ref.read(toastProvider.notifier).showError(a.localPath != null
          ? 'This file uploads when you post the note.'
          : 'This file has no link to open.');
      return;
    }
    // Anything else can only be rendered by the OS viewer.
    await _launch(url);
  }

  /// Hands the link to the browser / document viewer, reporting a refusal.
  Future<void> _launch(String url) async {
    final failure = await openAttachment(url);
    if (failure == null || !mounted) return;
    ref.read(toastProvider.notifier).showError(failure);
  }

  Widget _attachmentChip(NoteAttachment a, {VoidCallback? onRemove}) {
    final failed = a.failed;
    final chip = Container(
      padding: EdgeInsets.fromLTRB(8.w, 6.h, onRemove != null ? 6.w : 10.w, 6.h),
      decoration: BoxDecoration(
        color: failed ? AppColors.tintRed : const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(9.r),
        border: Border.all(color: failed ? AppColors.error : const Color(0xFFE6E7EA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A failed upload gets its own glyph regardless of file type — the
          // point is to catch the eye as "something's wrong here", not to say
          // what kind of file it was.
          if (failed)
            Icon(PhosphorIconsFill.warningCircle, size: 15.sp, color: AppColors.error)
          // The photo itself, not a generic glyph — a row of identically
          // named camera files is otherwise impossible to tell apart.
          else if (attachmentImage(a) case final img?)
            ClipRRect(
              borderRadius: BorderRadius.circular(4.r),
              child: Image(
                image: img,
                width: 18.w,
                height: 18.w,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(PhosphorIconsFill.image,
                    size: 15.sp, color: AppColors.blueBright),
              ),
            )
          else
            Icon(a.isImage ? PhosphorIconsFill.image : PhosphorIconsFill.filePdf,
                size: 15.sp, color: a.isImage ? AppColors.blueBright : AppColors.error),
          SizedBox(width: 6.w),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 120.w),
            child: Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 600.0)], fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textBody)),
          ),
          if (failed) ...[
            SizedBox(width: 6.w),
            Text('Failed', style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 700.0)], fontSize: 10.5.sp, fontWeight: FontWeight.w700, color: AppColors.error)),
          ] else if (a.size != null) ...[
            SizedBox(width: 6.w),
            Text(a.size!, style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 400.0)], fontSize: 10.5.sp, color: AppColors.textPlaceholder)),
          ],
          if (onRemove != null) ...[
            SizedBox(width: 4.w),
            GestureDetector(
              onTap: onRemove,
              child: Icon(PhosphorIconsBold.x, size: 13.sp, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openAttachment(a),
      child: chip,
    );
  }

  Widget _viaPill(String via) {
    final isCall = via.toLowerCase() == 'call';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
      decoration: BoxDecoration(color: const Color(0xFFEFF4FB), borderRadius: BorderRadius.circular(6.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              isCall
                  ? PhosphorIconsFill.phone
                  : via.toLowerCase() == 'email'
                      ? PhosphorIconsFill.envelope
                      : PhosphorIconsFill.tag,
              size: 11.sp,
              color: AppColors.navy),
          SizedBox(width: 4.w),
          Text(via, style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 600.0)], fontSize: 11.sp, fontWeight: FontWeight.w600, color: AppColors.navy)),
        ],
      ),
    );
  }

  Widget _avatar(String initials, Color color, double size) {
    return Container(
      width: size.w,
      height: size.w,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(fontFamily: 'Manrope', fontVariations: const [FontVariation('wght', 700.0)], fontSize: (size * 0.34).sp, fontWeight: FontWeight.w700, color: AppColors.white)),
    );
  }
}

class _EditNoteDialog extends StatefulWidget {
  const _EditNoteDialog({required this.initial});

  final String initial;

  @override
  State<_EditNoteDialog> createState() => _EditNoteDialogState();
}

class _EditNoteDialogState extends State<_EditNoteDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit note'),
      content: TextField(
        controller: _ctrl,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(hintText: 'Edit note…', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()), child: const Text('Save')),
      ],
    );
  }
}

/// Webapp "Name this attachment" prompt, after Insert picks a file.
class _NameAttachmentDialog extends StatefulWidget {
  const _NameAttachmentDialog({required this.initial});

  final String initial;

  @override
  State<_NameAttachmentDialog> createState() => _NameAttachmentDialogState();
}

class _NameAttachmentDialogState extends State<_NameAttachmentDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this attachment'),
      content: TextField(controller: _ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()), child: const Text('OK')),
      ],
    );
  }
}
