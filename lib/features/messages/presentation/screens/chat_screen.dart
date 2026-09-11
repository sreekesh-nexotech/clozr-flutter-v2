import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../crm/application/providers/lead_call_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/whatsapp_template.dart';
import '../../application/providers/messages_providers.dart';
import '../components/chat_avatar.dart';
import '../components/message_bubble.dart';
import '../messages_tokens.dart';

/// Chat — a single conversation thread: header (avatar, status, call, tabs),
/// the Chats / Medias / Links panes, and a composer whose affordance depends on
/// the 24-hour window (free-form input vs. template-only). Recreates design
/// lines 5757–5861.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _draftCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _draftCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatTabProvider.notifier).state = 'chats';
      _scrollToEnd();
    });
  }

  @override
  void dispose() {
    _draftCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get _id => GoRouterState.of(context).uri.queryParameters['id'] ?? '';

  void _scrollToEnd() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
  }

  void _send() {
    final text = _draftCtrl.text.trim();
    if (text.isEmpty) return;
    ref.read(conversationsProvider.notifier).sendMessage(_id, text);
    _draftCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  /// Places a call to the contact: Exotel click-to-call when the org has
  /// telephony connected and this user is a configured agent (server rings the
  /// agent, then bridges to the contact and logs it itself); otherwise falls
  /// back to the device dialler. Mirrors [LeadCallService], but a WhatsApp
  /// contact may have no linked lead — Exotel still places and logs the call
  /// via reverse number resolution in that case; the dialler fallback simply
  /// has nothing to attach a manual CRM log to.
  Future<void> _call(Conversation chat) async {
    final toast = ref.read(toastProvider.notifier);
    final firstName = chat.name.split(' ').first;
    final to = normaliseCallNumber(chat.phone.isEmpty ? '' : '+${chat.phone}');
    if (to.isEmpty) {
      toast.show('No phone number for this contact');
      return;
    }

    final exotel = ref.read(exotelRemoteDataSourceProvider);
    final status = ref.read(exotelStatusValueProvider);
    final blocked = ref.read(exotelBlockedProvider);

    if (exotel != null && blocked == null && (status.usable || !status.known)) {
      try {
        await exotel.placeCall(leadId: chat.leadId, toNumber: to);
        if (mounted) toast.show('Calling $firstName…');
        return;
      } on Object catch (e) {
        // Refused — nothing was dialled; fall through to the device dialler.
        if (e is AppError && isExotelConfigRefusal(e.message)) {
          ref.read(exotelBlockedProvider.notifier).state = e.message;
        }
      }
    }

    final opened = await launchUrl(Uri(scheme: 'tel', path: to));
    if (!mounted) return;
    toast.show(opened ? 'Calling $firstName…' : 'Could not start the call.');
  }

  /// Lets the user pick a photo or a document, client-side size checks it
  /// against the same caps the backend enforces (`whatsapp.md` §4.5 — 5 MB
  /// images, 10 MB documents), then hands it to the composer as an optimistic
  /// outgoing bubble.
  Future<void> _pickAttachment() async {
    final kind = await showClozrSheet<String>(
      context: context,
      builder: (_) => const _AttachmentPickerSheet(),
    );
    if (kind == null || !mounted) return;
    final isImage = kind == 'image';

    final result = await FilePicker.platform.pickFiles(
      type: isImage ? FileType.image : FileType.any,
      withData: false, // path only — a large file should not sit in memory
    );
    final file = result?.files.firstOrNull;
    final path = file?.path;
    if (path == null || !mounted) return; // cancelled

    final limit = isImage ? 5 * 1024 * 1024 : 10 * 1024 * 1024;
    if (file!.size > limit) {
      ref.read(toastProvider.notifier).show(
          isImage ? 'Image too large — max 5 MB' : 'File too large — max 10 MB');
      return;
    }

    ref.read(conversationsProvider.notifier).sendAttachment(_id, path, file.name, isImage: isImage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  /// Opens the emoji picker in a sheet. Emoji are ordinary Unicode characters
  /// inserted into the composer's text — there is no backend endpoint for
  /// this and none is needed (`whatsapp.md` §4.1); handing the picker the
  /// same [_draftCtrl] the text field uses makes it insert at the caret (and
  /// back up on the picker's own backspace key) with no manual splicing.
  void _openEmojiPicker() {
    FocusScope.of(context).unfocus(); // drop the keyboard so the sheet has room
    showClozrSheet<void>(
      context: context,
      builder: (_) => SizedBox(
        height: 380.h,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(title: 'Emoji'),
            Expanded(
              child: EmojiPicker(
                textEditingController: _draftCtrl,
                config: Config(
                  height: 320.h,
                  emojiViewConfig: EmojiViewConfig(emojiSizeMax: 26.sp),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens an image/document bubble in the OS viewer.
  ///
  /// Just sent → the local file is still on the device, so it opens straight
  /// off [ChatMessage.attachmentPath] (whatsapp.md §5: "the optimistic bubble
  /// should render the local File object URL"). Otherwise — a later session,
  /// a cleared cache — it falls back to the authenticated media proxy via
  /// [ChatMessage.mediaId], writes the bytes to a temp file, then opens that.
  Future<void> _openAttachment(ChatMessage m) async {
    final toast = ref.read(toastProvider.notifier);
    final localPath = m.attachmentPath;
    if (localPath != null && await File(localPath).exists()) {
      await _launchLocalFile(localPath, toast);
      return;
    }

    final mediaId = m.mediaId;
    if (mediaId == null) {
      toast.show('This attachment is no longer available.');
      return;
    }
    await _fetchAndOpenMedia(mediaId, toast);
  }

  /// The Medias tab's download row — same proxy fetch as [_openAttachment]'s
  /// fallback, since a media-tab row never has a local file to open straight
  /// off (it did not necessarily originate on this device).
  Future<void> _downloadMedia(ChatMedia f) async {
    final toast = ref.read(toastProvider.notifier);
    final mediaId = f.mediaId;
    if (mediaId == null) {
      toast.show('This attachment is no longer available.');
      return;
    }
    await _fetchAndOpenMedia(mediaId, toast);
  }

  /// Authenticated media proxy → temp file → OS viewer. Shared tail for
  /// [_openAttachment] and [_downloadMedia] once each has settled on a
  /// `mediaId` to fetch.
  Future<void> _fetchAndOpenMedia(String mediaId, ToastController toast) async {
    final fetched = await ref.read(conversationsProvider.notifier).fetchMedia(mediaId);
    if (!mounted) return;
    if (fetched == null) {
      toast.show('Could not open this file — it may have expired.');
      return;
    }
    final (bytes, contentType) = fetched;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/wa_$mediaId${_extensionForMime(contentType)}');
    await file.writeAsBytes(bytes);
    if (!mounted) return;
    await _launchLocalFile(file.path, toast);
  }

  Future<void> _launchLocalFile(String path, ToastController toast) async {
    final result = await OpenFile.open(path);
    if (result.type != ResultType.done && mounted) {
      toast.show(result.message.isNotEmpty ? result.message : 'No app on this device can open this file.');
    }
  }

  /// A file extension guess from the media proxy's `Content-Type` — the
  /// filename WhatsApp gave the row isn't always present, but the OS viewer
  /// still needs *an* extension to pick an app.
  String _extensionForMime(String? mime) {
    switch ((mime ?? '').split(';').first.trim().toLowerCase()) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'application/pdf':
        return '.pdf';
      case 'application/msword':
        return '.doc';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return '.docx';
      case 'application/vnd.ms-excel':
        return '.xls';
      case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        return '.xlsx';
      case 'text/csv':
        return '.csv';
      case 'application/zip':
        return '.zip';
      default:
        return '';
    }
  }

  /// Open the "Template messages" picker sheet (closed 24-hour window). Tapping a
  /// row sends THAT template — the body resolved with the contact's first name —
  /// flagged as a template, then closes the sheet and toasts.
  void _openTemplateSheet(Conversation chat) {
    final firstName = chat.name.split(' ').first;
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => _TemplatePickerSheet(
        firstName: firstName,
        onPick: (t) {
          Navigator.of(ctx).pop();
          ref.read(conversationsProvider.notifier).sendTemplate(_id, t.resolve(firstName));
          ref.read(toastProvider.notifier).show('Template message sent');
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(conversationByIdProvider(_id));
    final tab = ref.watch(chatTabProvider);

    if (chat == null) {
      return Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            _header(context, null, tab),
            const Expanded(child: Center(child: Text('Conversation not found'))),
          ],
        ),
      );
    }

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _header(context, chat, tab),
          Expanded(child: _pane(tab, chat)),
        ],
      ),
    );
  }

  // ── Header ──
  Widget _header(BuildContext context, Conversation? chat, String tab) {
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 54.h, 14.w, 0),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft, width: 1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.canPop() ? context.pop() : context.go(Routes.messages),
                  child: Padding(
                    padding: EdgeInsets.only(right: 6.w),
                    child: Icon(PhosphorIconsBold.caretLeft, size: 22.sp, color: AppColors.textPrimary),
                  ),
                ),
                if (chat != null) ...[
                  ChatAvatar(initials: chat.initials, online: chat.online, size: 40, fontSize: 13),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (chat.leadId != null) {
                          context.push('${Routes.leadDetail}?id=${chat.leadId}');
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 16, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.2)),
                          SizedBox(height: 1.h),
                          Text(chat.online ? 'Online' : 'Last seen ${chat.lastTime}',
                              style: AppText.custom(
                                  size: 11.5,
                                  weight: FontWeight.w600,
                                  color: chat.online ? AppColors.success : AppColors.textPlaceholder)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _call(chat),
                    child: Container(
                      width: 38.w,
                      height: 38.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11.r),
                        border: Border.all(color: AppColors.borderChip, width: 1),
                      ),
                      child: Icon(PhosphorIconsFill.phone, size: 18.sp, color: AppColors.navy),
                    ),
                  ),
                ] else
                  Text('Chat', style: AppText.custom(size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
              ],
            ),
          ),
          if (chat != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              child: Row(
                children: [
                  for (final t in const [('chats', 'Chats'), ('medias', 'Medias'), ('links', 'Links')]) ...[
                    _tab(t.$1, t.$2, tab == t.$1),
                    SizedBox(width: 22.w),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tab(String key, String label, bool active) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(chatTabProvider.notifier).state = key,
      child: Container(
        padding: EdgeInsets.only(top: 4.h, bottom: 12.h),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.navy : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(label,
            style: AppText.custom(
                size: 14,
                weight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.navy : AppColors.textPlaceholder)),
      ),
    );
  }

  // ── Panes ──
  Widget _pane(String tab, Conversation chat) {
    switch (tab) {
      case 'medias':
        return _mediaPane(chat);
      case 'links':
        return _linksPane(chat);
      default:
        return _chatsPane(chat);
    }
  }

  Widget _chatsPane(Conversation chat) {
    return Column(
      children: [
        Expanded(
          child: chat.messages.isEmpty
              ? ListView(
                  children: [
                    _emptyBlock(
                      icon: PhosphorIconsRegular.chatCircleDots,
                      iconBg: AppColors.tintGreen,
                      iconColor: AppColors.success,
                      title: 'No messages yet',
                      body: 'Say hello to start the conversation with ${chat.name}.',
                    ),
                  ],
                )
              : ListView(
                  controller: _scrollCtrl,
                  padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 10.h),
                  children: [
                    _todayChip(),
                    for (final m in chat.messages)
                      MessageBubble(
                        message: m,
                        onRetry: m.failed
                            ? () => ref.read(conversationsProvider.notifier).retryMessage(chat.id, m)
                            : null,
                        onOpenAttachment: m.isAttachment ? () => _openAttachment(m) : null,
                      ),
                  ],
                ),
        ),
        _composer(chat),
      ],
    );
  }

  Widget _composer(Conversation chat) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 26.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft, width: 1)),
      ),
      child: chat.windowOpen ? _openComposer(chat) : _closedComposer(chat),
    );
  }

  Widget _openComposer(Conversation chat) {
    final hasDraft = _draftCtrl.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _windowBanner(
          bg: AppColors.tintGreen,
          icon: PhosphorIconsRegular.clock,
          iconColor: AppColors.success,
          title: 'Within 24-hour window',
          titleColor: AppColors.success,
          sub: '${chat.windowLeft} · free-form messaging allowed',
          subColor: MessagesColors.windowSub,
        ),
        SizedBox(height: 10.h),
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openEmojiPicker,
              child: Icon(PhosphorIconsRegular.smiley, size: 24.sp, color: MessagesColors.muted),
            ),
            SizedBox(width: 9.w),
            Expanded(
              child: Container(
                height: 44.h,
                padding: EdgeInsets.symmetric(horizontal: 15.w),
                decoration: BoxDecoration(
                  color: AppColors.bgScreen,
                  borderRadius: BorderRadius.circular(22.r),
                  border: Border.all(color: MessagesColors.inputBorder, width: 1),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _draftCtrl,
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                  style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textBody),
                  cursorColor: AppColors.navy,
                  // The backend caps `body` at 4096 chars (whatsapp.md §4.1)
                  // and measures the decoded string, not UTF-16 code units —
                  // Flutter's own maxLength enforcement is grapheme-aware
                  // (via `characters`), so a flag emoji counts as one, matching.
                  maxLength: 4096,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    counterText: '',
                    hintText: 'Type a message…',
                    hintStyle: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                  ),
                ),
              ),
            ),
            SizedBox(width: 9.w),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickAttachment,
              child: Icon(PhosphorIconsRegular.paperclip, size: 22.sp, color: MessagesColors.muted),
            ),
            SizedBox(width: 9.w),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _send,
              child: Container(
                width: 44.w,
                height: 44.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hasDraft ? AppColors.navy : MessagesColors.sendDisabled,
                  shape: BoxShape.circle,
                ),
                child: Icon(PhosphorIconsFill.paperPlaneTilt, size: 19.sp, color: AppColors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _closedComposer(Conversation chat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _windowBanner(
          bg: AppColors.bgChipGrey,
          icon: PhosphorIconsRegular.lockSimple,
          iconColor: MessagesColors.muted,
          title: '24-hour window closed',
          titleColor: AppColors.textLabelAlt,
          sub: 'Only approved template messages can be sent now.',
          subColor: AppColors.textMuted,
        ),
        SizedBox(height: 10.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openTemplateSheet(chat),
          child: Container(
            height: 46.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsRegular.paperPlaneTilt, size: 16.sp, color: AppColors.white),
                SizedBox(width: 8.w),
                Text('Send a template message',
                    style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.white)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _windowBanner({
    required Color bg,
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color titleColor,
    required String sub,
    required Color subColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1.h),
            child: Icon(icon, size: 15.sp, color: iconColor),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: titleColor)),
                SizedBox(height: 1.h),
                Text(sub, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: subColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayChip() {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(color: MessagesColors.todayChip, borderRadius: BorderRadius.circular(8.r)),
          child: Text('Today',
              style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textMuted2)),
        ),
      ),
    );
  }

  // ── Medias ──
  Widget _mediaPane(Conversation chat) {
    if (chat.media.isEmpty) {
      return ListView(children: [
        _emptyBlock(
          icon: PhosphorIconsRegular.image,
          iconBg: AppColors.bgChipGrey,
          iconColor: AppColors.textPlaceholder,
          title: 'No media shared',
          body: 'Photos and documents shared in this chat will appear here.',
        ),
      ]);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 30.h),
      children: [
        for (final f in chat.media)
          _fileRow(
            // The seed carries its own icon; an API row carries the kind and
            // picks from the same set here, so both render identically.
            icon: f.icon ?? _mediaIcon(f.kind),
            iconBg: AppColors.tintBlue,
            iconColor: AppColors.blueBright,
            title: f.name,
            sub: f.meta,
            subColor: AppColors.textPlaceholder,
            trailing: GestureDetector(
              onTap: () => _downloadMedia(f),
              child: Icon(PhosphorIconsRegular.downloadSimple, size: 18.sp, color: MessagesColors.muted),
            ),
          ),
      ],
    );
  }

  /// [ChatMedia.kind] → the row's icon. The kinds come from the message's
  /// WhatsApp type and mime (see `mediaKind`).
  IconData _mediaIcon(String kind) {
    switch (kind) {
      case 'image':
        return PhosphorIconsRegular.image;
      case 'video':
        return PhosphorIconsRegular.videoCamera;
      case 'audio':
        return PhosphorIconsRegular.musicNote;
      case 'pdf':
        return PhosphorIconsRegular.filePdf;
      case 'sheet':
        return PhosphorIconsRegular.fileXls;
      case 'doc':
        return PhosphorIconsRegular.fileDoc;
    }
    return PhosphorIconsRegular.file;
  }

  // ── Links ──
  Widget _linksPane(Conversation chat) {
    if (chat.links.isEmpty) {
      return ListView(children: [
        _emptyBlock(
          icon: PhosphorIconsRegular.linkSimple,
          iconBg: AppColors.bgChipGrey,
          iconColor: AppColors.textPlaceholder,
          title: 'No links shared',
          body: 'Links shared in this chat will appear here.',
        ),
      ]);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 30.h),
      children: [
        for (final lk in chat.links)
          _fileRow(
            icon: PhosphorIconsRegular.linkSimple,
            iconBg: AppColors.bgChipGrey,
            iconColor: AppColors.textLabelAlt,
            title: lk.title,
            sub: lk.url,
            subColor: AppColors.blueBright,
            subWeight: FontWeight.w600,
            trailing: Text(lk.meta,
                style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          ),
      ],
    );
  }

  Widget _fileRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String sub,
    required Color subColor,
    required Widget trailing,
    FontWeight subWeight = FontWeight.w500,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 2.w),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.bgLight, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11.r)),
            child: Icon(icon, size: 19.sp, color: iconColor),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 2.h),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 11.5, weight: subWeight, color: subColor)),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          trailing,
        ],
      ),
    );
  }

  Widget _emptyBlock({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 40.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56.r,
            height: 56.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(16.r)),
            child: Icon(icon, size: 26.sp, color: iconColor),
          ),
          SizedBox(height: 14.h),
          Text(title, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 5.h),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 230.w),
            child: Text(body,
                textAlign: TextAlign.center,
                style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted).copyWith(height: 1.5)),
          ),
        ],
      ),
    );
  }
}

/// The "Template messages" picker sheet (design ≈ line 6757). Lists the approved
/// WhatsApp templates: name (bold) with an APPROVED badge and a preview of the
/// body with the contact's first name substituted, hairline-divided between
/// rows. Tapping a row fires [onPick] with that template.
///
/// It watches the template providers directly: mock mode always has the seed;
/// API mode shows a loading state while the fetch is in flight and an empty
/// state when there are no approved templates — never the mock seed (audit
/// L-10).
class _TemplatePickerSheet extends ConsumerWidget {
  const _TemplatePickerSheet({
    required this.firstName,
    required this.onPick,
  });

  final String firstName;
  final ValueChanged<WhatsappTemplate> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(whatsappTemplatesProvider);
    final loading = ref.watch(whatsappTemplatesLoadingProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader(title: 'Template messages'),
        Container(
          margin: EdgeInsets.fromLTRB(18.w, 0, 18.w, 4.h),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: MessagesColors.infoBannerBg,
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1.h),
                child: Icon(PhosphorIconsRegular.info, size: 15.sp, color: AppColors.blueBright),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text('Only approved templates can be sent outside the 24-hour window.',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textLabelAlt)
                        .copyWith(height: 1.5)),
              ),
            ],
          ),
        ),
        if (templates.isEmpty)
          _placeholder(loading)
        else
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 26.h),
              child: Column(
                children: [
                  for (int i = 0; i < templates.length; i++)
                    _row(templates[i], last: i == templates.length - 1),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Shown when there are no templates to list: a spinner while the approved
  /// list is still loading, otherwise an honest empty state.
  Widget _placeholder(bool loading) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 26.h, 24.w, 34.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: loading
            ? [
                SizedBox(
                  width: 24.r,
                  height: 24.r,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy),
                ),
                SizedBox(height: 14.h),
                Text('Loading templates…',
                    style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textMuted)),
              ]
            : [
                Container(
                  width: 56.r,
                  height: 56.r,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(16.r)),
                  child: Icon(PhosphorIconsRegular.chatText, size: 26.sp, color: AppColors.textPlaceholder),
                ),
                SizedBox(height: 14.h),
                Text('No approved templates',
                    style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 5.h),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 240.w),
                  child: Text('Approved WhatsApp templates will appear here once they are set up.',
                      textAlign: TextAlign.center,
                      style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted).copyWith(height: 1.5)),
                ),
              ],
      ),
    );
  }

  Widget _row(WhatsappTemplate t, {required bool last}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPick(t),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 2.w),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: last ? Colors.transparent : AppColors.bgChipGrey, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(11.r)),
              child: Icon(PhosphorIconsRegular.whatsappLogo, size: 19.sp, color: AppColors.success),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                      ),
                      SizedBox(width: 8.w),
                      _approvedBadge(),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(t.resolve(firstName),
                      style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)
                          .copyWith(height: 1.5)),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: Icon(PhosphorIconsFill.paperPlaneTilt, size: 18.sp, color: AppColors.navy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _approvedBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
      decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(6.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsFill.sealCheck, size: 10.sp, color: AppColors.success),
          SizedBox(width: 4.w),
          Text('APPROVED',
              style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.success, letterSpacing: 0.4)),
        ],
      ),
    );
  }
}

/// The paperclip's "Photo / Document" picker. Only these two, matching what
/// the backend can actually send (`whatsapp.md` §4.4) — no camera, sticker,
/// location, or contact-card options, since there is no endpoint behind them.
class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader(title: 'Attach'),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 30.h),
          child: Column(
            children: [
              _row(
                context,
                icon: PhosphorIconsRegular.image,
                label: 'Photo',
                sub: 'Images up to 5 MB',
                value: 'image',
              ),
              SizedBox(height: 10.h),
              _row(
                context,
                icon: PhosphorIconsRegular.file,
                label: 'Document',
                sub: 'Any file up to 10 MB',
                value: 'document',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String sub,
    required String value,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(value),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.borderCardSoft),
        ),
        child: Row(
          children: [
            Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.tintBlue, borderRadius: BorderRadius.circular(11.r)),
              child: Icon(icon, size: 18.sp, color: AppColors.blueBright),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(sub, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                ],
              ),
            ),
            Icon(PhosphorIconsRegular.caretRight, size: 16.sp, color: AppColors.textPlaceholder),
          ],
        ),
      ),
    );
  }
}
