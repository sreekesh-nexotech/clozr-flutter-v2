import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_service.dart';
import '../../../../core/network/network_providers.dart';
import '../quote_discount_approval_rules.dart';
import 'crm_module_schema_providers.dart';
import 'quotes_providers.dart';

/// `GET /quotations/discount-approvals/` — admins see the org's requests,
/// everyone else their own and their reporting subtree's.
const _approvalsPath = '/quotations/discount-approvals/';

typedef DiscountApprovalPage = ({int count, List<DiscountApproval> rows});

/// Inbox page for one tab: (status, pageSize).
final quoteDiscountApprovalsProvider =
    FutureProvider.autoDispose.family<DiscountApprovalPage, ({String status, int pageSize})>((ref, q) async {
  final body = await ref
      .read(apiServiceProvider)
      .get(_approvalsPath, query: {'status': q.status, 'page': 1, 'page_size': q.pageSize});
  return discountApprovalPage(body);
});

/// The newest request for one quote (by UUID) — carries `can_decide` and the
/// reviewer's comment for the detail banner. Null when there is none or the
/// read fails.
final quoteLatestDiscountApprovalProvider =
    FutureProvider.autoDispose.family<DiscountApproval?, String>((ref, quotationUuid) async {
  if (quotationUuid.isEmpty) return null;
  // Re-read whenever the quote's approval state changes (a save that raises a
  // new request, a decision) — otherwise the banner keeps the previous,
  // already-decided request and offers the approver no Approve / Reject.
  ref.watch(quoteRowProvider(quotationUuid)
      .select((v) => '${v.valueOrNull?['approval_status']}|${v.valueOrNull?['discount_pct']}'));
  try {
    final body = await ref
        .read(apiServiceProvider)
        .get(_approvalsPath, query: {'quotation': quotationUuid, 'page': 1, 'page_size': 5}, quiet: true);
    final rows = discountApprovalPage(body).rows;
    return rows.isEmpty ? null : rows.first;
  } on Object {
    return null;
  }
});

/// Quotes toolbar badge: pending requests (first 50) this user may decide;
/// 0 on any failure. Pair with [discountApprovalsLabel] for the tooltip.
final quoteDiscountApprovalsBadgeProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final body = await ref
        .read(apiServiceProvider)
        .get(_approvalsPath, query: {'status': 'pending', 'page': 1, 'page_size': 50}, quiet: true);
    return decidableCount(discountApprovalPage(body).rows);
  } on Object {
    return 0;
  }
});

/// `POST quotations/{uuid}/approve-discount/` or `reject-discount/` with an
/// optional `{comment}`. Throws `AppError`.
Future<void> postQuoteDiscountDecision(ApiService api, String quotationUuid,
    {required bool approve, String comment = ''}) async {
  final c = comment.trim();
  await api.post('/quotations/quotations/$quotationUuid/${approve ? 'approve-discount' : 'reject-discount'}/',
      body: c.isEmpty ? <String, dynamic>{} : {'comment': c});
}

/// After a decision: the inbox, the badge, the quote record and the lists.
void invalidateAfterDiscountDecision(WidgetRef ref, String quotationUuid) {
  ref.invalidate(quoteDiscountApprovalsProvider);
  ref.invalidate(quoteDiscountApprovalsBadgeProvider);
  ref.invalidate(quoteLatestDiscountApprovalProvider);
  if (quotationUuid.isNotEmpty) ref.invalidate(quoteRowProvider(quotationUuid));
  ref.invalidate(quotesProvider);
}
