import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/paginated.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../shell/application/providers/shell_providers.dart';

/// The org's sendable WhatsApp templates (approved, not disabled), raw.
final sendableWhatsappTemplatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final body = await ref.read(apiServiceProvider).get(
    ApiEndpoints.whatsappTemplates,
    query: {'page_size': 100},
    quiet: true,
  );
  return [
    for (final t in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results)
      if ('${t['status'] ?? 'APPROVED'}'.toUpperCase() == 'APPROVED' && t['is_active'] != false) t,
  ];
});

/// The webapp's draft WhatsApp chat for a lead with no conversation yet: the
/// 24-hour window is closed, so the first message must be a template. Sending
/// one starts the thread.
Future<void> showWhatsappDraftSheet(
  BuildContext context, {
  required String name,
  required String phoneDigits,
  required VoidCallback onSent,
}) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _DraftSheet(
      name: name,
      phoneDigits: phoneDigits,
      onSent: onSent,
    ),
  );
}

class _DraftSheet extends ConsumerStatefulWidget {
  const _DraftSheet({
    required this.name,
    required this.phoneDigits,
    required this.onSent,
  });

  final String name;
  final String phoneDigits;
  final VoidCallback onSent;

  @override
  ConsumerState<_DraftSheet> createState() => _DraftSheetState();
}

class _DraftSheetState extends ConsumerState<_DraftSheet> {
  bool _sending = false;

  static String _pretty(String raw) {
    final p = raw.replaceAll('_', ' ');
    return p.isEmpty ? p : p[0].toUpperCase() + p.substring(1);
  }

  static String _bodyOf(Map<String, dynamic> t) {
    final comps = t['components'];
    if (comps is List) {
      for (final c in comps) {
        if (c is Map && '${c['type']}'.toUpperCase() == 'BODY') return '${c['text'] ?? ''}';
      }
    }
    return '';
  }

  Future<void> _send(Map<String, dynamic> t) async {
    if (_sending) return;
    setState(() => _sending = true);
    final toast = ref.read(toastProvider.notifier);
    try {
      await ref.read(apiServiceProvider).post(ApiEndpoints.whatsappSendTemplate, body: {
        'whatsapp_account_id': t['whatsapp_account'] ?? t['whatsapp_account_id'] ?? t['account'],
        'to': widget.phoneDigits,
        'template_name': '${t['name']}',
        'language_code': '${t['language'] ?? t['language_code'] ?? 'en_US'}',
      });
    } on AppError catch (e) {
      if (mounted) setState(() => _sending = false);
      toast.showError(e.message);
      return;
    }
    if (!mounted) return;
    toast.show('Template sent');
    Navigator.of(context).pop();
    widget.onSent();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sendableWhatsappTemplatesProvider);
    final templates = async.valueOrNull ?? const [];
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader(title: widget.name.isEmpty ? '+${widget.phoneDigits}' : widget.name),
          Padding(
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 10.h),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(10.r),
              decoration: BoxDecoration(color: AppColors.tintAmber, borderRadius: BorderRadius.circular(10.r)),
              child: Row(children: [
                Icon(PhosphorIconsRegular.lockSimple, size: 14.sp, color: AppColors.warningDeep),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text('New chat — template required',
                      style: AppText.captionStrong(color: AppColors.warningDeep)),
                ),
              ]),
            ),
          ),
          Flexible(
            child: async.isLoading
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : templates.isEmpty
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(18.w, 6.h, 18.w, 6.h),
                        child: Text('No approved templates yet — add one in WhatsApp → Templates on the web.',
                            style: AppText.body(color: AppColors.textMuted)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final t in templates)
                            ListTile(
                              title: Text(_pretty('${t['name'] ?? ''}'), style: AppText.bodyStrong()),
                              subtitle: Text(_bodyOf(t), maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: Icon(PhosphorIconsFill.paperPlaneRight, size: 16.sp, color: AppColors.navy),
                              onTap: _sending ? null : () => _send(t),
                            ),
                        ],
                      ),
          ),
          // Webapp: the draft chat is template-only and never leaves the app,
          // so there is no hand-off to the device's WhatsApp here.
          SizedBox(height: 12.h),
        ],
      ),
    );
  }
}
