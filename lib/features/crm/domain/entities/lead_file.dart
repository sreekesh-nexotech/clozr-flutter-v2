import 'package:equatable/equatable.dart';

/// A file attached to a lead — one row of the Files tab. Maps
/// `/crm/attachments/`, which is a shared generic-relation table (leads,
/// customers, tasks, quotations, …); this entity covers the lead case.
class LeadFile extends Equatable {
  final String id;
  final String name;

  /// CDN URL of the stored file; `''` when the row carries no usable link.
  final String url;

  /// Optional caption entered at upload time.
  final String description;

  /// Uploader user id, already mapped through `UserDirectory` (so the signed-in
  /// user reads as `'me'`).
  final String uploadedBy;

  /// Display timestamp: "2d ago" / "9 Jul".
  final String uploadedAt;

  const LeadFile({
    required this.id,
    required this.name,
    required this.url,
    required this.uploadedBy,
    required this.uploadedAt,
    this.description = '',
  });

  /// Uppercased file extension ("PDF", "PNG") derived from the name, falling
  /// back to the URL. `'FILE'` when neither carries one.
  String get ext {
    for (final source in [name, url]) {
      final clean = source.split('?').first;
      final dot = clean.lastIndexOf('.');
      if (dot > 0 && dot < clean.length - 1) {
        final raw = clean.substring(dot + 1);
        if (raw.length <= 5 && !raw.contains('/')) return raw.toUpperCase();
      }
    }
    return 'FILE';
  }

  @override
  List<Object?> get props => [id];
}
