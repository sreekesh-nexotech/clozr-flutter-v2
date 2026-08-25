import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// One option from an org-configured CRM catalog — a pipeline stage
/// (`/crm/lead-statuses/`), a lead source (`/crm/lead-sources/`), and so on.
///
/// Carries the admin-set display [name] and dot [color] so lists and filters
/// render the org's own vocabulary ("Contacted", "Proposal Sent") instead of
/// the built-in `StatusMeta$` one, in the org's own colours.
class CatalogOption extends Equatable {
  const CatalogOption({
    required this.id,
    required this.name,
    this.color,
    this.statusType,
    this.isConverted = false,
    this.isClosed = false,
    this.isCancelled = false,
  });

  /// Server UUID (`lead_status_id`, `lead_source_id`, …).
  final String id;

  /// Admin-set display name, shown verbatim.
  final String name;

  /// Admin-set dot colour; null when the org left it blank.
  final Color? color;

  /// Fixed backend type code for lead statuses (`new` | `in_progress` | `won` |
  /// `lost` | `junk`). Null for catalogs that have no type.
  final String? statusType;

  /// Quote statuses only: the org's "Accepted" lane.
  ///
  /// Quotations have no `status_type` table, so this flag is the only way to
  /// know which status converts. Moving a quote **into** it makes the server
  /// create the invoice (`Payment` + `PaymentRecord`s) and moving out deletes
  /// them — see `quotation-schema-and-list-view-api.md` §4. False everywhere
  /// else.
  final bool isConverted;

  /// Project-task statuses only: whether the status closes the task, and
  /// whether it closes it as *cancelled* rather than done
  /// (`operations.md` §13.4).
  ///
  /// These are what resolve the tick/untick targets for a subtask: complete is
  /// the first `isClosed && !isCancelled` by position, reopen the first
  /// non-closed one. Folding a status *name* would get "Done"/"Archived" wrong
  /// on any org that renamed them. False everywhere else.
  final bool isClosed;
  final bool isCancelled;

  /// The value list rows join on. The leads list serializer sends `status` and
  /// `lead_source` as display *names*, not ids, so the case-folded name — not
  /// [id] — is the join key.
  String get key => name.toLowerCase().trim();

  @override
  List<Object?> get props =>
      [id, name, color, statusType, isConverted, isClosed, isCancelled];
}
