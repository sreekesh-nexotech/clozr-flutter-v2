import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
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
    ref.read(chatTabProvider.notifier).state = 'chats';
    _draftCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
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
                    onTap: () => ref.read(toastProvider.notifier).show('Calling ${chat.name.split(' ').first}…'),
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
              onTap: () => ref.read(toastProvider.notifier).show('Emoji picker — coming soon'),
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
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: 'Type a message…',
                    hintStyle: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                  ),
                ),
              ),
            ),
            SizedBox(width: 9.w),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(toastProvider.notifier).show('Attach — file picker coming soon'),
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
            icon: f.icon,
            iconBg: AppColors.tintBlue,
            iconColor: AppColors.blueBright,
            title: f.name,
            sub: f.meta,
            subColor: AppColors.textPlaceholder,
            trailing: Icon(PhosphorIconsRegular.downloadSimple, size: 18.sp, color: MessagesColors.muted),
          ),
      ],
    );
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
