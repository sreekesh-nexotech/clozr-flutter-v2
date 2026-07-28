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
  });

  bool get isMine => owner == 'me';

  @override
  List<Object?> get props => [id];
}
