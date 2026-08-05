import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/quotes_providers.dart';
import '../../domain/entities/quote.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../components/crm_async.dart';
import '../components/finance_widgets.dart';
import '../components/status_sheet.dart';

/// Quote detail — header card with status/accept actions, related link, meta
/// rows, line items + totals, notes and activity.
class QuoteDetailScreen extends ConsumerWidget {
  const QuoteDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(quotesProvider);

    Widget scaffold(Widget child) => Container(
          color: AppColors.bgDetail,
          child: Column(
            children: [
              DetailAppBar(section: 'Quote', onBack: () => context.pop()),
              Expanded(child: child),
            ],
          ),
        );

    return async.when(
      loading: () => scaffold(const DetailSkeleton()),
      error: (e, _) => scaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => ref.invalidate(quotesProvider)),
      ),
      data: (_) => _buildQuote(context, ref, id, scaffold),
    );
  }

  Widget _buildQuote(
    BuildContext context,
    WidgetRef ref,
    String id,
    Widget Function(Widget) scaffold,
  ) {
    final quote = ref.watch(quoteByIdProvider(id));
    if (quote == null) {
      return scaffold(const EmptyState(
        icon: PhosphorIconsRegular.fileText,
        title: 'Quote not found',
        body: 'This quote may have been removed or you no longer have access to it.',
      ));
    }

    final lookup = ref.watch(crmPartyLookupProvider);
    final meta = StatusMeta$.quote[quote.status] ?? StatusMeta$.quote['draft']!;
    final owner = MockUsers.of(quote.owner);
    final party = lookup(custId: quote.custId, leadId: quote.leadId);
    final isCust = quote.custId != null && lookup(custId: quote.custId) != null;
    final canAccept = quote.status == 'sent' || quote.status == 'draft';

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Quote',
            name: quoteWho(quote, lookup),
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => ref.read(toastProvider.notifier).show('Quote actions'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headerCard(context, ref, quote, meta, canAccept),
                SizedBox(height: 14.h),
                if (party != null) ...[
                  _relatedCard(context, quote, party, isCust),
                  SizedBox(height: 14.h),
                ],
                FinanceCard(
                  title: 'Quote details',
                  child: Column(
                    children: [
                      MetaRow(label: 'Template', value: quote.template),
                      MetaRow(label: 'Payment type', value: quote.payType),
                      MetaRow(label: 'Currency', value: quote.currency),
                      MetaRow(label: 'Valid until', value: quote.valid),
                      MetaRow(label: 'Due date', value: quote.dueDate.isEmpty ? '—' : quote.dueDate, last: true),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                _lineItemsCard(quote, owner),
                if (quote.note != null && quote.note!.isNotEmpty) ...[
                  SizedBox(height: 14.h),
                  FinanceCard(
                    title: 'Notes',
                    child: Text(quote.note!,
                        style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.6)),
                  ),
                ],
                SizedBox(height: 14.h),
                NotesCard(
                  title: 'Internal notes',
                  onSend: (_) => ref.read(toastProvider.notifier).show('Note added'),
                ),
                SizedBox(height: 14.h),
                FinanceCard(
                  title: 'Activity',
                  child: Padding(
                    padding: EdgeInsets.only(top: 6.h),
                    child: ActivityTimeline(entries: _activity(quote, owner.name)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(BuildContext context, WidgetRef ref, Quote quote, StatusMeta meta, bool canAccept) {
    final lookup = ref.watch(crmPartyLookupProvider);
    final issued = quote.issued == '—' ? 'Not issued yet' : 'Issued ${quote.issued}';
    final validity = quote.valid == '—' ? 'no validity set' : 'valid till ${quote.valid}';

    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconChip(icon: PhosphorIconsRegular.fileText, size: 46, radius: 13, iconSize: 22),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${quote.id}',
                            style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        SizedBox(width: 8.w),
                        StatusPill.meta(meta),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text(quoteWho(quote, lookup),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 4.h),
                    Text('$issued · $validity',
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              Expanded(
                flex: canAccept ? 10 : 10,
                child: GestureDetector(
                  onTap: () => _openStatusSheet(context, ref, quote),
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: const Color(0xFFE6E7EA)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
                        SizedBox(width: 8.w),
                        Text(meta.label, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textBody)),
                        SizedBox(width: 6.w),
                        Icon(PhosphorIconsBold.caretDown, size: 11.sp, color: AppColors.textMuted2),
                      ],
                    ),
                  ),
                ),
              ),
              if (canAccept) ...[
                SizedBox(width: 10.w),
                Expanded(
                  flex: 14,
                  child: GestureDetector(
                    onTap: () => ref.read(toastProvider.notifier).show('Quote accepted · invoice generated'),
                    child: Container(
                      height: 44.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.check, size: 15.sp, color: AppColors.white),
                          SizedBox(width: 7.w),
                          Text('Accept & invoice',
                              style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                GestureDetector(
                  onTap: () => ref.read(toastProvider.notifier).show('Quote rejected'),
                  child: Container(
                    width: 44.w,
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: const Color(0xFFF3C1C1), width: 1.5),
                    ),
                    child: Icon(PhosphorIconsBold.x, size: 16.sp, color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _relatedCard(BuildContext context, Quote quote, CrmParty party, bool isCust) {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
      onTap: () {
        if (isCust) {
          context.push('${Routes.customerDetail}?id=${quote.custId}');
        } else {
          context.push('${Routes.leadDetail}?id=${quote.leadId}');
        }
      },
      child: Row(
        children: [
          const IconChip(icon: PhosphorIconsRegular.buildings, size: 42, radius: 12, iconSize: 20),
          SizedBox(width: 13.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RELATED',
                    style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
                SizedBox(height: 2.h),
                Text(party.company,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 1.h),
                Text('${isCust ? 'Customer' : 'Lead'} · #${isCust ? quote.custId : quote.leadId}',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 15.sp, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }

  Widget _lineItemsCard(Quote quote, AppUser owner) {
    final sub = quote.amountNum.toDouble();
    return FinanceCard(
      title: 'Line items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final it in quote.items)
            Container(
              padding: EdgeInsets.symmetric(vertical: 11.h),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.name, style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text('Qty ${it.qty} · ${it.rate}',
                            style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                      ],
                    ),
                  ),
                  SizedBox(width: 14.w),
                  Text(it.amt, style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ),
          SizedBox(height: 13.h),
          _totalRow('Subtotal', _fmt(sub), muted: true),
          SizedBox(height: 7.h),
          _totalRow('GST (18%)', _fmt(sub * 0.18), muted: true),
          SizedBox(height: 10.h),
          Container(
            padding: EdgeInsets.only(top: 10.h),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('TOTAL',
                    style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
                const Spacer(),
                Text(_fmt(sub * 1.18),
                    style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
              ],
            ),
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 13)),
          Row(
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: owner.color, shape: BoxShape.circle),
                child: Text(owner.initials, style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.white)),
              ),
              SizedBox(width: 11.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(owner.name, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text('Quote owner', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool muted = false}) {
    return Row(
      children: [
        Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
        const Spacer(),
        Text(value, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
      ],
    );
  }

  List<ActivityEntry> _activity(Quote quote, String ownerName) {
    final entries = <ActivityEntry>[
      ActivityEntry(
        icon: PhosphorIconsRegular.fileText,
        tone: AppColors.blueBright,
        bg: AppColors.tintBlue,
        title: 'Quote created',
        sub: 'Issued ${quote.issued == '—' ? '—' : quote.issued} · $ownerName',
      ),
    ];
    if (quote.status != 'draft') {
      entries.insert(
        0,
        ActivityEntry(
          icon: PhosphorIconsRegular.paperPlaneTilt,
          tone: AppColors.warning,
          bg: AppColors.tintAmber,
          title: 'Sent to client',
          sub: quote.valid == '—' ? 'Awaiting validity' : 'Valid till ${quote.valid}',
        ),
      );
    }
    if (quote.status == 'accepted' || quote.status == 'rejected' || quote.status == 'expired') {
      final accepted = quote.status == 'accepted';
      final label = (StatusMeta$.quote[quote.status] ?? StatusMeta$.quote['draft']!).label.toLowerCase();
      entries.insert(
        0,
        ActivityEntry(
          icon: accepted ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.xCircle,
          tone: accepted ? AppColors.success : AppColors.error,
          bg: accepted ? AppColors.tintGreen : AppColors.tintRed,
          title: 'Quote $label',
          sub: accepted ? 'Invoice generated from this quote' : 'Closed without conversion',
        ),
      );
    }
    return entries;
  }

  Future<void> _openStatusSheet(BuildContext context, WidgetRef ref, Quote quote) async {
    const order = ['draft', 'sent', 'accepted', 'rejected', 'expired'];
    final chosen = await showStatusSheet(
      context: context,
      title: 'Quote status',
      currentKey: quote.status,
      options: [for (final k in order) StatusOption(k, StatusMeta$.quote[k]!)],
    );
    if (chosen != null && chosen != quote.status) {
      ref.read(toastProvider.notifier).show('Status set to ${StatusMeta$.quote[chosen]!.label}');
    }
  }

  /// The prototype's `fmt` for the totals block: Cr above ₹1Cr, else L.
  String _fmt(double v) {
    if (v >= 10000000) {
      var s = (v / 10000000).toStringAsFixed(2);
      if (s.endsWith('.00')) s = s.substring(0, s.length - 3);
      return '₹${s}Cr';
    }
    var s = (v / 100000).toStringAsFixed(1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return '₹${s}L';
  }
}
