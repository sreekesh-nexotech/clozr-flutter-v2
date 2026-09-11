import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import '../../features/shell/application/providers/shell_providers.dart';
import '../models/note.dart';
import '../utils/attachment_link.dart';
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
  });

  final List<NoteEntry> notes;
  /// Who the composer is writing as — supply from `noteAuthorProvider`.
  final NoteAuthor author;

  /// Called when the user posts a new note with any pending attachments.
  final void Function(String body, List<NoteAttachment> attachments) onAddNote;

  /// Called when the user replies to note [noteId].
  final void Function(String noteId, String body) onAddReply;

  @override
  ConsumerState<NotesThread> createState() => NotesThreadState();
}

class NotesThreadState extends ConsumerState<NotesThread> {
  final _noteCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();
  final _noteFocus = FocusNode();
  final List<NoteAttachment> _pending = [];
  String? _openReplyFor;

  /// Focuses the composer — used by the "add note" affordance in the sticky bar.
  void focusComposer() => _noteFocus.requestFocus();

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
    widget.onAddNote(body, List.of(_pending));
    _noteCtrl.clear();
    setState(() => _pending.clear());
    FocusScope.of(context).unfocus();
  }

  void _sendReply(String noteId) {
    final body = _replyCtrl.text.trim();
    if (body.isEmpty) return;
    widget.onAddReply(noteId, body);
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
                  style: TextStyle(fontFamily: 'Manrope', fontSize: 15.sp, fontWeight: FontWeight.w700, color: const Color(0xFF14151A))),
              SizedBox(width: 8.w),
              Text('${widget.notes.length}',
                  style: TextStyle(fontFamily: 'Manrope', fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
          ),
          SizedBox(height: 13.h),
          _composer(),
          if (_pending.isNotEmpty) _pendingChips(),
          SizedBox(height: 2.h),
          for (final n in widget.notes) _noteRow(n),
        ],
      ),
    );
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
                    style: TextStyle(fontFamily: 'Manrope', fontSize: 14.sp, color: AppColors.textBody),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Add a note…',
                      hintStyle: TextStyle(fontFamily: 'Manrope', fontSize: 14.sp, color: AppColors.textPlaceholder),
                    ),
                  ),
                ),
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
    return Container(
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
                        style: TextStyle(fontFamily: 'Manrope', fontSize: 13.5.sp, fontWeight: FontWeight.w700, color: const Color(0xFF14151A))),
                    if (n.via != null) _viaPill(n.via!),
                    Text(n.time, style: TextStyle(fontFamily: 'Manrope', fontSize: 11.sp, fontWeight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                ),
                if (n.body.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Text(n.body,
                        style: TextStyle(fontFamily: 'Manrope', fontSize: 14.sp, height: 1.55, color: const Color(0xFF363636))),
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
                GestureDetector(
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
                          style: TextStyle(fontFamily: 'Manrope', fontSize: 12.5.sp, fontWeight: FontWeight.w600, color: const Color(0xFF6B6B6B)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
                    Text(r.author, style: TextStyle(fontFamily: 'Manrope', fontSize: 12.5.sp, fontWeight: FontWeight.w700, color: const Color(0xFF14151A))),
                    Text(r.time, style: TextStyle(fontFamily: 'Manrope', fontSize: 10.5.sp, fontWeight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(top: 3.h),
                  child: Text(r.body, style: TextStyle(fontFamily: 'Manrope', fontSize: 13.sp, height: 1.5, color: const Color(0xFF444444))),
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
                style: TextStyle(fontFamily: 'Manrope', fontSize: 13.sp, color: AppColors.textBody),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Write a reply…',
                  hintStyle: TextStyle(fontFamily: 'Manrope', fontSize: 13.sp, color: AppColors.textPlaceholder),
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
                style: TextStyle(fontFamily: 'Manrope', fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textBody)),
          ),
          if (failed) ...[
            SizedBox(width: 6.w),
            Text('Failed', style: TextStyle(fontFamily: 'Manrope', fontSize: 10.5.sp, fontWeight: FontWeight.w700, color: AppColors.error)),
          ] else if (a.size != null) ...[
            SizedBox(width: 6.w),
            Text(a.size!, style: TextStyle(fontFamily: 'Manrope', fontSize: 10.5.sp, color: AppColors.textPlaceholder)),
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
          Icon(isCall ? PhosphorIconsFill.phone : PhosphorIconsFill.envelope, size: 11.sp, color: AppColors.navy),
          SizedBox(width: 4.w),
          Text(via, style: TextStyle(fontFamily: 'Manrope', fontSize: 11.sp, fontWeight: FontWeight.w600, color: AppColors.navy)),
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
          style: TextStyle(fontFamily: 'Manrope', fontSize: (size * 0.34).sp, fontWeight: FontWeight.w700, color: AppColors.white)),
    );
  }
}
