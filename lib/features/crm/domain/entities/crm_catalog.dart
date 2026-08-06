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

  /// The value list rows join on. The leads list serializer sends `status` and
  /// `lead_source` as display *names*, not ids, so the case-folded name — not
  /// [id] — is the join key.
  String get key => name.toLowerCase().trim();

  @override
  List<Object?> get props => [id, name, color, statusType];
}
