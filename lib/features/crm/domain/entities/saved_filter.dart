import 'package:equatable/equatable.dart';

/// A named filter preset — the bookmark chip above a list.
///
/// [definition] is the backend's `LeadFilter` param dict, stored and returned
/// **verbatim**; it is the canonical form. The drawer's own value objects are
/// derived from it on demand via `LeadFilterCodec`, never persisted, because
/// translating needs the org catalogs and those load asynchronously.
class SavedFilter extends Equatable {
  const SavedFilter({
    required this.id,
    required this.name,
    required this.definition,
    this.isValid = true,
    this.invalidReason,
    this.order = 0,
  });

  /// `saved_filter_id`. Locally-created presets (mock mode) use a synthetic id.
  final String id;
  final String name;
  final Map<String, dynamic> definition;

  /// Server-set. A definition referencing a purged custom field comes back
  /// `false`; such a filter **fails inert** — it never runs, so it can never
  /// widen a result set. Render it greyed rather than hiding it, so the user
  /// can see what needs fixing.
  final bool isValid;
  final String? invalidReason;

  final int order;

  @override
  List<Object?> get props => [id, name, definition, isValid, order];
}
