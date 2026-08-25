/// The Billing screen's three backed records.
///
/// There is no `billing.md`: these shapes were read off the live endpoints
/// (`/billing/invoices/`, `/billing/storage/`, `/billing/plans/`), so every
/// field is defensive — a key that stops arriving degrades the row rather than
/// failing the card.
library;

/// One subscription invoice (`GET /billing/invoices/`).
class BillingInvoice {
  const BillingInvoice({
    required this.id,
    required this.number,
    required this.status,
    this.total = 0,
    this.amountDue = 0,
    this.periodStart,
    this.periodEnd,
    this.dueDate,
    this.paidAt,
    this.lineItems = const [],
  });

  final String id;

  /// `INV-2026-08-…-008` — what the row is called.
  final String number;

  /// The server's own word: `paid`, `pending`, … Not folded onto a built-in
  /// vocabulary; the pill shows what the API said.
  final String status;
  final double total;
  final double amountDue;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final List<BillingLineItem> lineItems;

  bool get isPaid => status.toLowerCase() == 'paid';

  /// True when money is still owed, whatever the status word says.
  bool get isOutstanding => amountDue > 0;
}

/// One line on an invoice — a licence charge, a prorated adjustment.
class BillingLineItem {
  const BillingLineItem({
    required this.description,
    this.quantity = 0,
    this.subtotal = 0,
    this.isProrated = false,
  });

  final String description;
  final int quantity;
  final double subtotal;
  final bool isProrated;
}

/// The org's file usage (`GET /billing/storage/`).
///
/// `limit_*` and `percent` are **null on an unlimited plan**, which is what the
/// dev org is on — so a card that renders "14 GB / 50 GB" is inventing both
/// halves of the fraction.
class StorageUsage {
  const StorageUsage({
    this.usedDisplay = '',
    this.limitDisplay,
    this.percent,
    this.unlimited = false,
  });

  /// Pre-formatted by the server ("8.88 MB"), so the app does not re-derive it.
  final String usedDisplay;
  final String? limitDisplay;

  /// 0–100, or null when there is no cap to be a fraction of.
  final double? percent;
  final bool unlimited;

  /// What the headline reads: "8.88 MB of 50 GB", or just the amount used when
  /// nothing caps it.
  String get headline {
    if (unlimited || limitDisplay == null || limitDisplay!.isEmpty) {
      return usedDisplay.isEmpty ? '—' : usedDisplay;
    }
    return '$usedDisplay of ${limitDisplay!}';
  }

  /// The bar's fill, 0–1. Zero when unlimited — a full bar would read as a
  /// quota about to run out.
  double get fraction {
    final p = percent;
    if (unlimited || p == null) return 0;
    return (p / 100).clamp(0.0, 1.0);
  }
}

/// A subscription plan (`GET /billing/plans/`).
class BillingPlan {
  const BillingPlan({
    required this.id,
    required this.name,
    this.description = '',
    this.monthlyPerUser = 0,
    this.annualPerUser = 0,
    this.minUsers,
    this.maxUsers,
    this.features = const {},
  });

  final String id;
  final String name;
  final String description;
  final double monthlyPerUser;
  final double annualPerUser;
  final int? minUsers;
  final int? maxUsers;

  /// The plan's feature flags and caps, as the API sends them: booleans plus
  /// dotted limit keys (`limits.users`, `limits.projects`). A null limit means
  /// uncapped.
  final Map<String, dynamic> features;

  /// The modules this plan switches on, in the order the API listed them.
  List<String> get enabledModules =>
      [for (final e in features.entries) if (e.value == true) e.key];

  /// "Up to 25 users", "Unlimited users" — null when the plan says nothing.
  String? get userLimitLabel {
    if (!features.containsKey('limits.users')) return null;
    final limit = features['limits.users'];
    if (limit == null) return 'Unlimited users';
    return 'Up to $limit users';
  }
}
