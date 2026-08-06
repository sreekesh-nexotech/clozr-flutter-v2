import 'package:equatable/equatable.dart';

/// What kind of thing happened, for choosing the timeline row's icon.
///
/// The generic `/access-control/audit-logs/` endpoint does **not** send the
/// pre-humanized `event_type`/`summary` that the project activity endpoints do,
/// so this is derived client-side from the raw row.
enum AuditEventKind {
  created,
  statusChanged,
  fieldChanged,
  noteAdded,
  childAdded,
  deleted,
  other,
}

/// One row of a record's activity log.
///
/// [title] and [subtitle] are already human-readable — the mapper does that
/// work, because the raw row is a field diff, not a sentence.
class AuditEntry extends Equatable {
  const AuditEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.at,
    this.actor = '',
  });

  final String id;
  final AuditEventKind kind;
  final String title;

  /// The detail line; may be empty when the title says everything.
  final String subtitle;

  /// When it happened. Null when the row carried no parsable timestamp.
  final DateTime? at;

  /// Who did it, by display name. Empty for a system-generated entry.
  final String actor;

  @override
  List<Object?> get props => [id];
}
