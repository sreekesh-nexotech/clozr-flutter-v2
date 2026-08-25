import 'package:equatable/equatable.dart';

/// A CRM task linked to a lead. Mirrors the prototype's `tasks` seed. The Ops
/// module has its own task entity — this one lives entirely in CRM.
class CrmTask extends Equatable {
  final String id;
  final String title;

  /// The task's `description`. A distinct field, never folded into [title]:
  /// the org's mobile layout lists both, and a headline that silently became
  /// the description is exactly the bug follow-ups had.
  ///
  /// Absent from the default list payload — it arrives only on the mobile card
  /// projection and on the detail retrieve.
  final String description;
  final String type; // key into TASKTYPES — Call / Email / Meeting / …
  final String? leadId;
  final String status; // key into StatusMeta$.task — todo / inprogress / blocked / done

  /// The org's own name for the status ("Open", "Cancelled"), kept verbatim
  /// alongside the folded [status] key.
  ///
  /// [status] folds every org lane into four built-in buckets, which is fine
  /// for colour and done-ness but wrong for anything the user reads: an org
  /// whose lanes are Open / In Progress / Completed / Cancelled would see them
  /// labelled "To do" / "Blocked" / "Done". The tabs and the card pill use this
  /// so they speak the org's vocabulary. Empty for mock rows, which have none.
  final String statusName;

  final String priority; // High / Medium / Low
  final String assignee; // user id
  final String due; // "16 Jun 2026"
  final String dueNote; // "2d overdue" / "Today" / "In 2d" / ""

    /// The row exactly as the API sent it.
  ///
  /// The typed fields cover the card's fixed frame; this is what makes the rest
  /// dynamic — a column the org adds to its layout is read from here by name,
  /// so a field nobody anticipated still renders.
  final Map<String, dynamic> raw;

  const CrmTask({
    this.raw = const {},
    required this.id,
    required this.title,
    this.description = '',
    required this.type,
    required this.leadId,
    required this.status,
    required this.priority,
    required this.assignee,
    required this.due,
    required this.dueNote,
    this.statusName = '',
  });

  bool get isMine => assignee == 'me';
  bool get isOverdue =>
      dueNote.toLowerCase().contains('overdue') && status != 'done';

  /// The clean title (strips the " — Company" suffix) used on cards.
  String get titleClean {
    final i = title.indexOf(' — ');
    return i > 0 ? title.substring(0, i) : title;
  }

  @override
  List<Object?> get props => [id];
}
