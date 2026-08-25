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
  });

  /// Whether the ticket was resolved after its resolution SLA expired. Null
  /// when either timestamp is missing — "not known", not "on time".
  bool? get resolvedAfterBreach {
    final done = DateTime.tryParse(resolvedISO ?? '');
    final due = DateTime.tryParse(resolveByISO ?? '');
    if (done == null || due == null) return null;
    return done.isAfter(due);
  }

  bool get isMine => assignees.contains('me');
  bool get isLocked => status == 'closed';
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
      );

  @override
  List<Object?> get props => [id, status, assignees];
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
