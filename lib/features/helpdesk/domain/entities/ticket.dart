import 'package:equatable/equatable.dart';

/// A helpdesk ticket. Fields mirror the prototype's `TKTSEED` records 1:1 so the
/// mock data source maps directly, and the shape is API-ready: when `/tickets`
/// lands, deserialize JSON into this exact entity and the UI is unchanged.
class Ticket extends Equatable {
  final String id;
  final String subject;
  final String cat; // Complaint / Request / Query …
  final String custId; // key into TicketDirectory.customers
  final String contact;
  final String channel; // Phone / Email / WhatsApp / Walk-in
  final String status; // key into StatusMeta$.ticket
  final String pri; // Urgent / High / Medium / Low
  final List<String> assignees; // user ids
  final String? product;
  final String? projId;
  final String? taskId;
  final String created;
  final String? responded;
  final String? resolved;
  final String? respByISO;
  final String? respByLabel;
  final String? resolveByISO;
  final String? resolveByLabel;
  final String desc;

  const Ticket({
    required this.id,
    required this.subject,
    required this.cat,
    required this.custId,
    required this.contact,
    required this.channel,
    required this.status,
    required this.pri,
    required this.assignees,
    required this.product,
    required this.projId,
    required this.taskId,
    required this.created,
    required this.responded,
    required this.resolved,
    required this.respByISO,
    required this.respByLabel,
    required this.resolveByISO,
    required this.resolveByLabel,
    required this.desc,
  });

  bool get isMine => assignees.contains('me');
  bool get isLocked => status == 'closed';
  bool get isPaused => status == 'pending';

  /// A shallow copy used by the detail screen's local status/assignee edits so
  /// the SLA banner + pills recompute without mutating the seed.
  Ticket copyWith({String? status, List<String>? assignees}) => Ticket(
        id: id,
        subject: subject,
        cat: cat,
        custId: custId,
        contact: contact,
        channel: channel,
        status: status ?? this.status,
        pri: pri,
        assignees: assignees ?? this.assignees,
        product: product,
        projId: projId,
        taskId: taskId,
        created: created,
        responded: responded,
        resolved: resolved,
        respByISO: respByISO,
        respByLabel: respByLabel,
        resolveByISO: resolveByISO,
        resolveByLabel: resolveByLabel,
        desc: desc,
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
