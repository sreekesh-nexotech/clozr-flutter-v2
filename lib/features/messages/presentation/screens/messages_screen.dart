import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../application/providers/messages_providers.dart';
import '../components/conversation_row.dart';
import '../messages_tokens.dart';

/// Messages — the conversation list. Custom back-header + search over a
/// scrolling list of conversation cards. Recreates design lines 5711–5752.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(chatSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(visibleConversationsProvider);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: rows.isEmpty
                ? ListView(
                    children: const [
                      EmptyState(
                        icon: PhosphorIconsRegular.chatsCircle,
                        title: 'No conversations found',
                        body: 'Try a different search, or start a chat from any lead.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 28.h),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10.h),
                    itemBuilder: (context, i) {
                      final c = rows[i];
                      return ConversationRow(
                        conversation: c,
                        onTap: () {
                          ref.read(conversationsProvider.notifier).markRead(c.id);
                          context.push('${Routes.chat}?id=${c.id}');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 0),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft, width: 1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                child: Padding(
                  padding: EdgeInsets.only(right: 4.w),
                  child: Icon(PhosphorIconsBold.caretLeft, size: 22.sp, color: AppColors.textPrimary),
                ),
              ),
              Container(
                width: 38.w,
                height: 38.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(11.r)),
                child: Icon(PhosphorIconsFill.chatsCircle, size: 20.sp, color: AppColors.success),
              ),
              SizedBox(width: 10.w),
              Text('Messages',
                  style: AppText.custom(size: 22, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
            ],
          ),
          SizedBox(height: 14.h),
          Container(
            height: 46.h,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: BoxDecoration(
              color: AppColors.bgScreen,
              borderRadius: BorderRadius.circular(13.r),
              border: Border.all(color: MessagesColors.inputBorder, width: 1),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.magnifyingGlass, size: 18.sp, color: AppColors.textPlaceholder),
                SizedBox(width: 10.w),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => ref.read(chatSearchProvider.notifier).state = v,
                    style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textBody),
                    cursorColor: AppColors.navy,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: 'Search conversations…',
                      hintStyle: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.h),
        ],
      ),
    );
  }
}
