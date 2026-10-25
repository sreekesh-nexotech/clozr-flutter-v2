// Quote discount approval (webapp plan 5.5) — the pure mapping and gating
// rules, mirroring the webapp's `salesLibrary.response.ts` (`toDiscountApproval`),
// `quoteSalesFormat.ts` (`pctLabel`), `quoteLifecycle.ts`
// (`isSendBlockedByApproval`, `acceptBlockReason`) and `QuoteDetailScreen.tsx`
// (`SEND_BLOCKED_COPY`, `APPROVAL_CHIP`). No Flutter here, so it is unit-tested.

/// A quote's `approval_status`: NOT_REQUIRED | PENDING | APPROVED | REJECTED.
/// Anything else (or a missing key) reads as NOT_REQUIRED, like the webapp.
String quoteApprovalStatus(Map<String, dynamic>? quote) {
  final v = '${quote?['approval_status'] ?? ''}'.trim().toUpperCase();
  return const ['NOT_REQUIRED', 'PENDING', 'APPROVED', 'REJECTED'].contains(v) ? v : 'NOT_REQUIRED';
}

/// "Mark as sent" waits for a pending / rejected discount approval
/// (server: 409 APPROVAL_PENDING).
bool isSendBlockedByApproval(Map<String, dynamic>? quote) {
  final s = quoteApprovalStatus(quote);
  return s == 'PENDING' || s == 'REJECTED';
}

const kMarkSentPendingApproval = 'Waiting for discount approval — it can be marked as sent once approved';
const kMarkSentRejectedApproval = 'The discount was not approved — reduce it before marking the quote as sent';
const kAcceptNeedsApproval = 'The discount needs approval before this quote can be accepted.';

/// Why "Mark as sent" is greyed by the discount approval; '' when it is not.
/// (The webapp shows its first-send content block — no line / no validity
/// date — ahead of this one.)
String markSentBlockedReason(Map<String, dynamic>? quote) {
  switch (quoteApprovalStatus(quote)) {
    case 'PENDING':
      return kMarkSentPendingApproval;
    case 'REJECTED':
      return kMarkSentRejectedApproval;
    default:
      return '';
  }
}

/// Accept refused because of the discount approval; '' when it is not.
String acceptBlockedByApprovalReason(Map<String, dynamic>? quote) =>
    isSendBlockedByApproval(quote) ? kAcceptNeedsApproval : '';

/// Webapp `acceptBlockReason`, minus the local sent / expired fallbacks: the
/// server's `acceptance_block.detail` when it sent one, else the approval
/// reason, else ''.
String acceptBlockedReason(Map<String, dynamic>? quote) {
  final block = quote?['acceptance_block'];
  if (block is Map) {
    final detail = '${block['detail'] ?? ''}'.trim();
    return detail.isEmpty ? 'This quote can’t be accepted right now.' : detail;
  }
  return acceptBlockedByApprovalReason(quote);
}

/// The detail header chip ("PENDING APPROVAL" / "APPROVED" / "APPROVAL
/// REJECTED"); null for NOT_REQUIRED.
String? approvalChipLabel(Map<String, dynamic>? quote) {
  switch (quoteApprovalStatus(quote)) {
    case 'PENDING':
      return 'PENDING APPROVAL';
    case 'APPROVED':
      return 'APPROVED';
    case 'REJECTED':
      return 'APPROVAL REJECTED';
    default:
      return null;
  }
}

/// Webapp `pctLabel`: "20%" / "12.5%" from a decimal string; '—' when empty.
String pctLabel(Object? value) {
  final s = value == null ? '' : '$value'.trim();
  if (s.isEmpty || s == 'null') return '—';
  final n = double.tryParse(s);
  if (n == null || !n.isFinite) return '$s%';
  final fixed = double.parse(n.toStringAsFixed(2));
  final txt = fixed == fixed.truncateToDouble() ? fixed.toInt().toString() : fixed.toString();
  return '$txt%';
}

String? _decimal(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

String _name(Object? user) {
  if (user is! Map) return '';
  final full = '${user['full_name'] ?? ''}'.trim();
  if (full.isNotEmpty) return full;
  return '${user['email'] ?? ''}'.trim();
}

/// One `/quotations/discount-approvals/` row.
class DiscountApproval {
  const DiscountApproval({
    required this.id,
    required this.quotationId,
    required this.quotationNumber,
    required this.quotationTitle,
    required this.status,
    required this.discountPct,
    required this.limitPct,
    required this.reason,
    required this.reviewComment,
    required this.requestedByName,
    required this.reviewedByName,
    required this.requestedAt,
    required this.reviewedAt,
    required this.canDecide,
  });

  final String id;

  /// The quote's UUID (the decide endpoints are addressed by it).
  final String quotationId;

  /// The display id ("QTN-00028") — the mobile detail route's `?id=`.
  final String quotationNumber;
  final String quotationTitle;

  /// pending | approved | rejected | cancelled.
  final String status;
  final String discountPct;
  final String? limitPct;
  final String reason;
  final String reviewComment;
  final String requestedByName;
  final String reviewedByName;
  final String requestedAt;
  final String reviewedAt;

  /// Server-computed: this user may approve / reject (approve permission and
  /// higher in the requester's reporting line).
  final bool canDecide;

  bool get isPending => status == 'pending';

  /// Approve / Reject show only on a pending row the server lets us decide.
  bool get showDecide => canDecide && isPending;

  /// QUOTE column headline: the title, else the number.
  String get headline => quotationTitle.isNotEmpty ? quotationTitle : quotationNumber;

  /// "Pending" / "Approved" / "Rejected" / "Cancelled".
  String get statusLabel => status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1);

  /// STATUS sub-line once decided: `Cijo G: “Keep it within 10%”`; '' otherwise.
  String get reviewLine {
    if (isPending || (reviewedByName.isEmpty && reviewComment.isEmpty)) return '';
    final comment = reviewComment.isEmpty ? '' : '${reviewedByName.isEmpty ? '' : ': '}“$reviewComment”';
    return '$reviewedByName$comment';
  }

  factory DiscountApproval.fromJson(Map<String, dynamic> r) {
    final status = '${r['status'] ?? ''}'.trim().toLowerCase();
    return DiscountApproval(
      id: '${r['approval_id'] ?? ''}',
      quotationId: '${r['quotation'] ?? ''}' == 'null' ? '' : '${r['quotation'] ?? ''}',
      quotationNumber: '${r['quotation_number'] ?? ''}',
      quotationTitle: '${r['quotation_title'] ?? ''}'.trim(),
      status: const ['pending', 'approved', 'rejected', 'cancelled'].contains(status) ? status : 'pending',
      discountPct: _decimal(r['discount_pct']) ?? '0.00',
      limitPct: _decimal(r['limit_pct']),
      reason: '${r['reason'] ?? ''}'.trim(),
      reviewComment: '${r['review_comment'] ?? ''}'.trim(),
      requestedByName: _name(r['requested_by']),
      reviewedByName: _name(r['reviewed_by']),
      requestedAt: '${r['requested_at'] ?? ''}' == 'null' ? '' : '${r['requested_at'] ?? ''}',
      reviewedAt: '${r['reviewed_at'] ?? ''}' == 'null' ? '' : '${r['reviewed_at'] ?? ''}',
      canDecide: r['can_decide'] == true,
    );
  }
}

/// A page of requests: `{count, results: [...]}`.
({int count, List<DiscountApproval> rows}) discountApprovalPage(Object? body) {
  final rows = body is Map && body['results'] is List
      ? [
          for (final r in body['results'] as List)
            if (r is Map) DiscountApproval.fromJson(Map<String, dynamic>.from(r)),
        ]
      : <DiscountApproval>[];
  final count = body is Map ? (body['count'] as num?)?.toInt() ?? rows.length : rows.length;
  return (count: count, rows: rows);
}

/// The toolbar badge: pending requests (first page) this user may decide.
int decidableCount(Iterable<DiscountApproval> rows) => rows.where((r) => r.showDecide).length;

/// Toolbar tooltip / semantics label.
String discountApprovalsLabel(int decidable) =>
    decidable > 0 ? 'Discount approvals — $decidable waiting for you' : 'Discount approvals';

/// Inbox empty state per tab.
({String title, String? body}) discountApprovalsEmpty(String status) => status == 'pending'
    ? (
        title: 'Nothing waiting for approval',
        body: 'Quotes whose discount is above the creator’s limit show up here until someone up the reporting line decides.',
      )
    : (title: 'No $status requests', body: null);

/// The decision dialog's lead-in, after the bold [quoteLabel]:
/// " has a 20% discount, above the requester’s 10% limit. Once approved it can be marked as sent."
String discountDecisionBody({required bool approve, required String discountPct, String? limitPct}) {
  final limit = (limitPct ?? '').isEmpty ? '' : ', above the requester’s ${pctLabel(limitPct)} limit';
  final tail = approve ? 'Once approved it can be marked as sent.' : 'It stays blocked from being sent until the discount is reduced.';
  return ' has a ${pctLabel(discountPct)} discount$limit. $tail';
}

/// The facts the detail banner shows, from the quote record and (optionally)
/// its newest approval request.
class DiscountBannerFacts {
  const DiscountBannerFacts({
    required this.pending,
    required this.discountPct,
    required this.limitPct,
    required this.requestedByName,
    required this.requestedAt,
    required this.reviewedByName,
    required this.reviewComment,
    required this.canDecide,
  });

  final bool pending;
  final String discountPct;
  final String? limitPct;
  final String requestedByName;
  final String requestedAt;
  final String reviewedByName;
  final String reviewComment;
  final bool canDecide;

  /// Null when the quote shows no banner (NOT_REQUIRED / APPROVED).
  static DiscountBannerFacts? from(Map<String, dynamic>? quote, DiscountApproval? latest) {
    if (!isSendBlockedByApproval(quote)) return null;
    final pending = quoteApprovalStatus(quote) == 'PENDING';
    final pend = quote?['pending_discount_approval'] is Map ? quote!['pending_discount_approval'] as Map : null;
    return DiscountBannerFacts(
      pending: pending,
      discountPct: _decimal(pend?['discount_pct']) ?? _decimal(quote?['discount_pct']) ?? '0.00',
      limitPct: _decimal(pend?['limit_pct']) ?? latest?.limitPct,
      requestedByName: _name(pend?['requested_by']),
      requestedAt: '${pend?['requested_at'] ?? ''}' == 'null' ? '' : '${pend?['requested_at'] ?? ''}',
      reviewedByName: latest?.reviewedByName ?? '',
      reviewComment: latest?.reviewComment ?? '',
      canDecide: pending && (latest?.showDecide ?? false),
    );
  }

  String get title => pending ? 'Discount approval pending.' : 'Discount approval rejected.';

  /// The sentence after the bold [title]. [dateLabel] formats `requested_at`.
  String body(String Function(String) dateLabel) {
    if (pending) {
      final b = StringBuffer(' ${pctLabel(discountPct)} discount');
      b.write((limitPct ?? '').isNotEmpty ? ' is above the ${pctLabel(limitPct)} limit' : ' is above the limit');
      if (requestedByName.isNotEmpty) b.write(' — requested by $requestedByName');
      if (requestedAt.isNotEmpty) b.write(' on ${dateLabel(requestedAt)}');
      b.write('. It can’t be marked as sent until it’s approved.');
      return b.toString();
    }
    final b = StringBuffer(' The ${pctLabel(discountPct)} discount was not approved');
    if (reviewedByName.isNotEmpty) b.write(' by $reviewedByName');
    if (reviewComment.isNotEmpty) b.write(' — “$reviewComment”');
    b.write('. Reduce the discount to send this quote.');
    return b.toString();
  }
}
