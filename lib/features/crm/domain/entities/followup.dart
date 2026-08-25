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
  /// The task's own `title` — the card's headline.
  ///
  /// Kept separate from [description]. Both were collapsed into one `agenda`
  /// field, with description winning when present, so a follow-up that had one
  /// lost its title entirely: the headline silently became the description and
  /// the real title was nowhere on screen. The org's mobile layout asks for
  /// both as distinct fields.
  final String title;

  /// The task's `description` — its own line on the card and detail page.
  final String description;

  /// What the record is *about*, for the places that want one line: the
  /// description when there is one, the title otherwise.
  ///
  /// A convenience over the two real fields, never a replacement — anything
  /// rendering a headline should read [title].
  String get agenda => description.isNotEmpty ? description : title;

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

    /// The row exactly as the API sent it.
  ///
  /// The typed fields cover the card's fixed frame; this is what makes the rest
  /// dynamic — a column the org adds to its layout is read from here by name,
  /// so a field nobody anticipated still renders.
  final Map<String, dynamic> raw;

  const Followup({
    this.raw = const {},
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
    this.title = '',
    this.description = '',
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
