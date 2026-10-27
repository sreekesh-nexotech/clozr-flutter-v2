import 'package:equatable/equatable.dart';

/// A helpdesk ticket. Fields mirror the prototype's `TKTSEED` records 1:1 so the
/// mock data source maps directly, and the shape is API-ready: when `/tickets`
/// lands, deserialize JSON into this exact entity and the UI is unchanged.
class Ticket extends Equatable {
  final String id;

  /// The org's human ticket number ("TKT-0025"). [id] is the `issue_id` uuid —
  /// the lookup key, not something to show a user. Empty when the backend has
  /// not minted one.
  final String reference;

  /// What to print where a ticket number belongs.
  String get displayRef => reference.isNotEmpty ? reference : id;
  final String subject;
  /// The org's own issue type ("Billing", "Integration") when the API names
  /// one; the built-in Complaint / Request / Query vocabulary otherwise.
  final String cat;

  /// `issue_type` — the uuid the edit form writes back. Empty for mock rows.
  final String typeId;
  final String custId; // key into TicketDirectory.customers
  final String contact;
  final String channel; // Phone / Email / WhatsApp / Walk-in
  final String status; // key into StatusMeta$.ticket

  /// The org's own status, as `/crm/issues/` reports it — `issue_status_id`
  /// and `name`.
  ///
  /// Kept beside the folded [status] because the two answer different
  /// questions: [status] picks the colour and the built-in vocabulary, these
  /// are what the org calls it — and what the drawer and `status__in` match on
  /// now that both come from `/crm/issue-statuses/`. Empty for mock rows.
  final String statusId;
  final String statusName;
  final String pri; // Urgent / High / Medium / Low (display)

  /// The priority the API stores — `Low | Medium | High | Critical`. [pri] is
  /// the display fold ("Critical" reads as "Urgent"); this is what the drawer
  /// offers and `priority__in` sends. Empty for mock rows.
  final String priorityName;
  final List<String> assignees; // user ids
  final String? product;

  /// The catalog `product_id` behind [product], which is only its display
  /// name. The edit form writes ids, not names.
  final String? productId;
  final String? projId;

  /// `project_name` as the row carries it, so the detail row and the
  /// linked-task chip do not have to resolve a uuid against a projects list
  /// that may not be loaded.
  final String? projName;
  final String? taskId;
  final String created;

  /// When the ticket was raised, as the API sent it — the list's "5m ago".
  final String? createdISO;
  final String? responded;
  final String? resolved;
  final String? respByISO;
  final String? respByLabel;
  final String? resolveByISO;
  final String? resolveByLabel;
  final String desc;

  /// When the ticket was actually resolved, as the API sent it. [resolved] is
  /// the display form ("12 Aug 2026"), which is day-precision — comparing that
  /// to [resolveByISO] cannot say whether an SLA measured in hours was met.
  final String? resolvedISO;

  /// When the first response actually went out, as the API sent it. Same
  /// reasoning as [resolvedISO]: [responded] is day-precision, so only this can
  /// say whether the response beat [respByISO].
  final String? respondedISO;

  /// Whether the first response landed after its deadline. Null when either
  /// side is unknown — "we cannot tell", which must not read as "on time".
  bool? get respondedLate => _after(respondedISO, respByISO);

  /// Whether the resolution landed after its deadline.
  bool? get resolvedLate => _after(resolvedISO, resolveByISO);

  static bool? _after(String? actual, String? deadline) {
    final a = DateTime.tryParse(actual ?? '');
    final d = DateTime.tryParse(deadline ?? '');
    if (a == null || d == null) return null;
    return a.isAfter(d);
  }

  /// Whether this ticket's work is chargeable to the customer.
  ///
  /// Read-only in the app for now: the write path filters unknown keys, so the
  /// flag can be shown but not set here. Set it in the web app.
  final bool billable;

  /// The amount to charge, as the decimal string the API sends. Null when the
  /// charge is carried by [billableProductId] instead.
  final String? billableAmount;

  /// The catalog product the charge is based on.
  final String? billableProductId;

  /// Set by accounting once the charge has actually been posted to a document.
  /// Null until then, and never editable from the app.
  final String? billedDocumentLineId;

  /// What the API itself says about the row — the org status' colour and
  /// flags, the pause-aware SLA clock, the raw category. Null for mock rows,
  /// which fall back to the folded fields above.
  final TicketServerFacts? facts;

  const Ticket({
    required this.id,
    this.reference = '',
    required this.subject,
    required this.cat,
    this.typeId = '',
    required this.custId,
    required this.contact,
    required this.channel,
    required this.status,
    this.statusId = '',
    this.statusName = '',
    required this.pri,
    this.priorityName = '',
    required this.assignees,
    required this.product,
    this.productId,
    required this.projId,
    this.projName,
    required this.taskId,
    required this.created,
    required this.responded,
    required this.resolved,
    required this.respByISO,
    required this.respByLabel,
    required this.resolveByISO,
    required this.resolveByLabel,
    required this.desc,
    this.resolvedISO,
    this.respondedISO,
    this.createdISO,
    this.billable = false,
    this.billableAmount,
    this.billableProductId,
    this.billedDocumentLineId,
    this.facts,
  });

  /// Whether accounting has posted the charge for this ticket.
  bool get isBilled => (billedDocumentLineId ?? '').isNotEmpty;

  /// Whether the ticket was resolved after its resolution SLA expired. Null
  /// when either timestamp is missing — "not known", not "on time".
  bool? get resolvedAfterBreach {
    final done = DateTime.tryParse(resolvedISO ?? '');
    final due = DateTime.tryParse(resolveByISO ?? '');
    if (done == null || due == null) return null;
    return done.isAfter(due);
  }

  bool get isMine => assignees.contains('me');
  /// Webapp `isIssueLocked`: a ticket in a resolved status (Resolved, Closed,
  /// Duplicate…) is read-only until it is reopened. The org's own
  /// `is_resolved` flag decides; mock rows fall back to the built-in key.
  bool get isLocked => facts != null ? facts!.statusResolved : status == 'closed';
  bool get isPaused => status == 'pending';

  /// A shallow copy used by the detail screen's local status/assignee edits so
  /// the SLA banner + pills recompute without mutating the seed.
  Ticket copyWith({String? status, List<String>? assignees}) => Ticket(
        id: id,
        reference: reference,
        subject: subject,
        cat: cat,
        typeId: typeId,
        custId: custId,
        contact: contact,
        channel: channel,
        status: status ?? this.status,
        statusId: statusId,
        statusName: statusName,
        pri: pri,
        priorityName: priorityName,
        assignees: assignees ?? this.assignees,
        product: product,
        productId: productId,
        projId: projId,
        projName: projName,
        taskId: taskId,
        created: created,
        responded: responded,
        resolved: resolved,
        respByISO: respByISO,
        respByLabel: respByLabel,
        resolveByISO: resolveByISO,
        resolveByLabel: resolveByLabel,
        desc: desc,
        resolvedISO: resolvedISO,
        respondedISO: respondedISO,
        createdISO: createdISO,
        // This method enumerates every field by hand, so anything added above
        // and forgotten here silently resets to its default on a status or
        // assignee change.
        billable: billable,
        billableAmount: billableAmount,
        billableProductId: billableProductId,
        billedDocumentLineId: billedDocumentLineId,
        facts: facts,
      );

  @override
  List<Object?> get props => [id, status, assignees];
}

/// The server's own facts about a ticket row (`/crm/issues/`), kept verbatim
/// so the list renders exactly what the webapp derives from the same fields.
class TicketServerFacts {
  const TicketServerFacts({
    this.statusColor,
    this.statusResolved = false,
    this.statusOnHold = false,
    this.typeName,
    this.customerName,
    this.contactName,
    this.contactId,
    this.reportedFor = 'client',
    this.assignedToId,
    this.assignedToName,
    this.hasSla = false,
    this.slaRemainingSeconds,
    this.slaHoldStarted = false,
    this.slaBreachedFlag = false,
    this.firstResponseDue = false,
    this.firstResponded = false,
    this.firstResponseRemainingSeconds,
    this.firstResponseBreached = false,
    this.channelCode,
    this.slaValue,
    this.slaUnit = '',
    this.parentIssueId,
    this.parentReference = '',
    this.parentSubject = '',
    this.childCount = 0,
    this.isChild = false,
    this.attachments = const [],
    this.replies = const [],
    this.customFields = const {},
  });

  /// The org status' own colour (`#3B82F6`), null when unset.
  final String? statusColor;
  final bool statusResolved;
  final bool statusOnHold;

  /// `type_name` — null for an uncategorised ticket (the webapp's "—").
  final String? typeName;
  final String? customerName;
  final String? contactName;

  /// The ticket form's own write values, read back for Edit Ticket: the
  /// picked contact (`contact` uuid), `reported_for` (`client` | `self`) and
  /// the single `assigned_to` user.
  final String? contactId;
  final String reportedFor;
  final String? assignedToId;
  final String? assignedToName;

  /// A deadline or a clock exists (webapp `hasSla`).
  final bool hasSla;

  /// Signed, pause-aware seconds to the resolution deadline (negative = late).
  final double? slaRemainingSeconds;
  final bool slaHoldStarted;
  final bool slaBreachedFlag;
  final bool firstResponseDue;
  final bool firstResponded;
  final double? firstResponseRemainingSeconds;
  final bool firstResponseBreached;

  /// The raw `channel` key (`email` / `whatsapp` / `phone` / `api`), null when
  /// unset — what decides whether a customer reply can be sent.
  final String? channelCode;

  /// The customer SLA snapshotted onto the ticket (`sla_value` / `sla_unit`);
  /// null value = the ticket has no SLA ("No SLA").
  final num? slaValue;
  final String slaUnit;

  /// Ticket hierarchy (two levels): the parent's uuid, reference and subject
  /// on a child; the number of direct children on a root.
  final String? parentIssueId;
  final String parentReference;
  final String parentSubject;
  final int childCount;
  final bool isChild;

  /// Files on the ticket (`attachments[]`, inline on the detail read).
  final List<TicketAttachment> attachments;

  /// The customer-facing replies sent through the channel — `notes[]` whose
  /// `kind` is not `internal` (internal notes live in the shared notes panel).
  final List<TicketReply> replies;

  /// Extra data a webhook-intake key stashed on the ticket (`custom_fields`).
  final Map<String, String> customFields;
}

/// One file on a ticket. [url] is the signed `file_url` (bare `file` 403s).
class TicketAttachment {
  const TicketAttachment({
    required this.id,
    required this.name,
    required this.url,
    this.uploadedAt,
    this.uploadedBy = '',
    this.uploadedById,
  });

  final String id;
  final String name;
  final String url;
  final DateTime? uploadedAt;
  final String uploadedBy;

  /// The uploader's `user_id` — all the detail read carries; the screen
  /// resolves the name from it.
  final String? uploadedById;
}

/// One reply sent to the customer from the ticket.
class TicketReply {
  const TicketReply({required this.id, required this.body, this.author = '', this.at});

  final String id;
  final String body;
  final String author;
  final DateTime? at;
}

/// A linked customer reference (company + contact name). The prototype resolves
/// `custId` against the shared customers roster; helpdesk keeps a lightweight
/// copy so it has no dependency on the CRM feature.
class TicketCustomer {
  final String id;
  final String name;
  final String company;
  const TicketCustomer(this.id, this.name, this.company);
  String get display => company.isNotEmpty ? company : name;
}

/// A linked project reference (name + estimated cost) used by the "Related
/// project" info row and the crossed-SLA ₹Value view.
class TicketProject {
  final String id;
  final String name;
  final String cost;
  const TicketProject(this.id, this.name, this.cost);
}

/// One SLA target row (`TKTSLA`), keyed by priority.
class SlaTarget {
  final String respLabel;
  final String resLabel;
  final String respISO;
  final String resISO;
  final String lineResp;
  final String lineRes;
  const SlaTarget({
    required this.respLabel,
    required this.resLabel,
    required this.respISO,
    required this.resISO,
    required this.lineResp,
    required this.lineRes,
  });
}
