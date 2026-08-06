import 'package:equatable/equatable.dart';

/// A scheduled follow-up (call / email / meeting / site visit). Mirrors the
/// prototype's `followups` seed. Linked to either a customer or a lead.
class Followup extends Equatable {
  final String id;
  final String kind; // key into FUKIND — Call / Email / Meeting / Site visit
  final String contact;
  final String? custId;
  final String? leadId;
  final String company;
  final String due; // "16 Jun 2026"
  final String time; // "09:30"
  final String status; // key into StatusMeta$.followup — overdue / due / done
  final String owner; // user id
  final String agenda;

  /// The org's own task status as the API sent it ("Open", "In Progress",
  /// "Cancelled"). Empty in mock mode.
  ///
  /// [status] folds this together with the due date into the three-way
  /// overdue/due/done bucket the card colours by — which cannot express
  /// "In Progress" or "Cancelled" at all. The raw name is what the status tabs
  /// and the Status filter join on.
  final String statusName;

  /// The org's priority name ("High", "Medium"). Empty when unset.
  final String priority;

  const Followup({
    required this.id,
    required this.kind,
    required this.contact,
    required this.custId,
    required this.leadId,
    required this.company,
    required this.due,
    required this.time,
    required this.status,
    required this.owner,
    required this.agenda,
    this.statusName = '',
    this.priority = '',
  });

  bool get isMine => owner == 'me';

  /// The value the status tabs and the Status filter join on: the org's own
  /// status name when the API sent one, else the derived bucket. One
  /// vocabulary at a time, for the same reason `Lead.stageKey` is.
  String get statusKey =>
      statusName.trim().isNotEmpty ? statusName.toLowerCase().trim() : status;

  @override
  List<Object?> get props => [id];
}
