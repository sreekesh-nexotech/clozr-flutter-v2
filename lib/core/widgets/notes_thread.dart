import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import '../models/note.dart';
import 'app_bottom_sheet.dart';

/// The shared Notes section used on every detail page (#13).
///
/// Renders the "Notes" card: a composer (avatar + input + attach + send) and a
/// thread where each note carries an optional source pill, attachment chips,
/// nested replies, and an inline reply composer. The host owns the [notes]
/// list and the mutation callbacks; this widget owns only the transient
/// composer/reply/attachment draft state.
class NotesThread extends StatefulWidget {
  const NotesThread({
    super.key,
    required this.notes,
    required this.onAddNote,
    required this.onAddReply,
    this.author = const NoteAuthor(),
  });

  final List<NoteEntry> notes;
  final NoteAuthor author;

  /// Called when the user posts a new note with any pending attachments.
  final void Function(String body, List<NoteAttachment> attachments) onAddNote;

  /// Called when the user replies to note [noteId].
  final void Function(String noteId, String body) onAddReply;

  @override
  State<NotesThread> createState() => NotesThreadState();
}

class NotesThreadState extends State<NotesThread> {
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

  /// Picks real files off the device and queues them for upload.
  ///
  /// Multi-select: the composer already renders a chip per pending file, and
  /// the upload loop posts them one at a time.
  Future<void> _pickFrom(FileType type) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowMultiple: true,
      withData: false, // paths only — a large file should not sit in memory
      allowedExtensions: type == FileType.custom ? _allowedExtensions : null,
    );
    if (result == null || !mounted) return; // cancelled

    setState(() {
      for (final f in result.files) {
        final path = f.path;
        if (path == null) continue;
        _pending.add(NoteAttachment(
          name: f.name,
          kind: _kindOf(f.extension),
          size: _formatBytes(f.size),
          localPath: path,
        ));
      }
    });
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

  Widget _attachmentChip(NoteAttachment a, {VoidCallback? onRemove}) {
    return Container(
      padding: EdgeInsets.fromLTRB(8.w, 6.h, onRemove != null ? 6.w : 10.w, 6.h),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(9.r),
        border: Border.all(color: const Color(0xFFE6E7EA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          if (a.size != null) ...[
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
