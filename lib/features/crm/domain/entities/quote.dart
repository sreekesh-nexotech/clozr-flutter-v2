import 'package:equatable/equatable.dart';

/// A single line item on a quote (product/service, qty, rate, amount).
class QuoteItem extends Equatable {
  final String name;

  /// Line quantity. A **double**, not an int: the serializer supports
  /// fractional quantities and sends them as decimal strings ("2.500"), so an
  /// int here silently collapsed every line to the `?? 1` fallback.
  final double qty;
  final String rate; // display, e.g. "₹9L"
  final String amt; // display, e.g. "₹9L"

  /// Per-line discount in rupees, already **subtracted** from [amt]/[amtNum] by
  /// the server. Shown so `qty × rate ≠ amt` has a visible explanation; never
  /// subtract it again.
  final double discount;

  /// The server's stable ordering key. Lines are sorted by it so an exploded
  /// package (component + adjustment lines) reads in the server's order.
  final int lineNo;

  /// The line total in rupees, for arithmetic.
  ///
  /// [amt] is a *display* string that `formatInr` abbreviates ("₹1.8L"), so
  /// summing it back by stripping non-digits reads 1.8 as 18 — the same trap
  /// that once had quotes raised at a fraction of their value. Anything adding
  /// lines up must use this.
  final int amtNum;

  const QuoteItem({
    required this.name,
    required this.qty,
    required this.rate,
    required this.amt,
    this.amtNum = 0,
    this.discount = 0,
    this.lineNo = 0,
  });

  @override
  List<Object?> get props => [name, qty, rate, amt, amtNum, discount, lineNo];
}

/// A CRM quote. Fields mirror the prototype's `quotes` seed 1:1 so the mock data
/// source maps directly and the shape is API-ready.
class Quote extends Equatable {
  /// The display id — `quotation_number` ("QTN-00004") when the row carries
  /// one. This is what the UI shows and what the route is keyed on.
  final String id;

  /// The record's `quotation_id` UUID.
  ///
  /// Every write and every related lookup addresses the quote by this, never by
  /// [id]: `PATCH /quotations/quotations/{quotation_id}/`, the audit log's
  /// `record_id`, the notes thread's `related_to_id`. Empty for mock rows, and
  /// for a payload that somehow omits it — callers must treat empty as "this
  /// record cannot be written to" rather than sending the display id, which
  /// resolves to nothing server-side.
  final String uuid;

  /// The org's own `quotation_title` ("Prefill check", "Mobile app smoke test").
  ///
  /// Null for mock rows, which have no equivalent. Worth carrying separately
  /// from the linked party: the list serializer trims to the org's visible
  /// columns, and an org that shows the title while hiding `lead`/`customer`
  /// sends this and nothing else nameable — leaving the card with no headline
  /// at all before it was mapped.
  final String? title;

  final String? custId;
  final String? leadId;
  final String status; // key into StatusMeta$.quote

  /// The org's own status name, verbatim ("Sent", "Under Review").
  ///
  /// Kept beside the folded [status] key rather than replacing it: the key
  /// still drives colour and the accept/reject affordances, while this is what
  /// the pill and the status tabs display. Empty for mock rows, and for a quote
  /// the org never set a status on — both fall back to the built-in vocabulary.
  final String statusName;
  final String amount; // display, e.g. "₹9L"
  final int amountNum; // sortable
  final String issued;
  final String valid;
  final String template;
  final String payType;
  final String currency;
  final String dueDate;
  final String owner; // user id
  final List<QuoteItem> items;
  final String? note;

  /// `EXCLUSIVE` / `INCLUSIVE`, or **null** when the serializer did not send it
  /// — which is the case on every deployment today.
  ///
  /// The screen used to label every total "TAX-FREE" unconditionally. That was
  /// a safe assumption while a quote carried no tax information at all; the
  /// accounting change can now contradict it, and a rep reading an INCLUSIVE
  /// quote as tax-free would quote the customer roughly the tax again on top.
  /// Null keeps the old wording, so nothing changes until the field arrives.
  final String? amountsAre;

  const Quote({
    required this.id,
    this.uuid = '',
    this.title,
    required this.custId,
    required this.leadId,
    required this.status,
    this.statusName = '',
    required this.amount,
    required this.amountNum,
    required this.issued,
    required this.valid,
    required this.template,
    required this.payType,
    required this.currency,
    required this.dueDate,
    required this.owner,
    required this.items,
    this.note,
    this.amountsAre,
  });

  /// True only when the server has explicitly said the amounts include tax.
  bool get isTaxInclusive => (amountsAre ?? '').toUpperCase() == 'INCLUSIVE';

  @override
  List<Object?> get props => [id];
}
