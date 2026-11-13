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

  /// The uploader's display name as the row carries it (`uploaded_by.full_name`);
  /// `''` when the row only has an id.
  final String uploaderName;

  /// Stored size in bytes (`size_bytes`); null when the row has none.
  final int? sizeBytes;

  /// `source.kind` — where the file was attached: the record itself (e.g.
  /// `issue`), or `note` for a file sent with one of its notes / replies.
  final String sourceKind;

  /// Attached to a note or reply rather than to the record directly.
  bool get fromNote => sourceKind == 'note';

  const LeadFile({
    required this.id,
    required this.name,
    required this.url,
    required this.uploadedBy,
    required this.uploadedAt,
    this.description = '',
    this.uploaderName = '',
    this.sizeBytes,
    this.sourceKind = '',
  });

  /// "4 B" / "12 KB" / "1.4 MB"; `''` when the size is unknown.
  String get sizeLabel {
    final b = sizeBytes;
    if (b == null || b < 0) return '';
    if (b < 1024) return '$b B';
    final kb = b / 1024;
    if (kb < 1024) return '${kb < 10 ? kb.toStringAsFixed(1) : kb.round()} KB';
    final mb = kb / 1024;
    return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
  }

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
