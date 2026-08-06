import 'package:dio/dio.dart';

import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/lead_file.dart';

/// Remote attachments (`/crm/attachments/`). HTTP + JSON → [LeadFile] mapping
/// only; caching lives in the API repository.
///
/// `/crm/attachments/` is one shared table behind a generic relation, so the
/// list is always scoped with `related_to` / `related_to_id`.
class AttachmentsRemoteDataSource {
  const AttachmentsRemoteDataSource(this._api);

  final ApiService _api;

  /// Raw rows for one lead, following `next` up to a sane page cap.
  Future<List<Map<String, dynamic>>> fetchFileRowsForLead(String leadId) async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= 50; page++) {
      final body = await _api.get(ApiEndpoints.attachments, query: {
        'related_to': 'lead',
        'related_to_id': leadId,
        'page_size': ApiConfig.defaultPageSize,
        if (page > 1) 'page': page,
      });
      final chunk = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      rows.addAll(chunk.results);
      if (!chunk.hasMore) break;
    }
    return rows;
  }

  /// Mapped file list for one lead (malformed rows are skipped, never fatal).
  Future<List<LeadFile>> fetchFilesForLead(String leadId) async =>
      mapRows(await fetchFileRowsForLead(leadId));

  /// `POST /crm/attachments/` (multipart) — uploads one picked file against a
  /// lead. `related_to`/`related_to_id` are **required** here (unlike on call
  /// logs, where the link is optional).
  Future<LeadFile?> uploadFileForLead({
    required String leadId,
    required String path,
    required String name,
    String description = '',
  }) async {
    final form = FormData.fromMap({
      'related_to': 'lead',
      'related_to_id': leadId,
      'name': name,
      if (description.isNotEmpty) 'description': description,
      'file_upload': await MultipartFile.fromFile(path, filename: name),
    });
    final res = await _api.postForm(ApiEndpoints.attachments, form);
    return res is Map<String, dynamic> ? fileFromJson(res) : null;
  }

  // ── mapping (static so the repository and tests reuse it) ──

  /// Maps rows and sorts them newest-first (the endpoint returns insertion
  /// order, which is the wrong way round for a file list).
  static List<LeadFile> mapRows(List<Map<String, dynamic>> rows) {
    final dated = <(DateTime?, LeadFile)>[];
    for (final row in rows) {
      final file = fileFromJson(row);
      if (file != null) dated.add((_uploadedAt(row), file));
    }
    dated.sort((a, b) {
      final x = a.$1, y = b.$1;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return [for (final d in dated) d.$2];
  }

  /// One list row → [LeadFile]. A row without an `attachment_id` returns null.
  static LeadFile? fileFromJson(Map<String, dynamic> json, {DateTime? now}) {
    final id = _str(json['attachment_id']);
    if (id == null) return null;

    final url = _str(json['file']) ?? _str(json['file_url']) ?? '';
    final uploader = json['uploaded_by'] ?? json['created_by'];
    UserDirectory.registerJson(uploader);

    return LeadFile(
      id: id,
      // `name` defaults to the uploaded filename server-side, but an older row
      // can still carry an empty one — fall back to the URL's last segment.
      name: _str(json['name']) ?? _fileNameFromUrl(url) ?? 'Attachment',
      url: url,
      description: _str(json['description'])?.trim() ?? '',
      uploadedBy: UserDirectory.mapUserId(
          uploader is Map ? _str(uploader['user_id']) : _str(uploader)),
      uploadedAt: relativeTime(_uploadedAt(json), now: now),
    );
  }

  /// The row's timestamp — `uploaded_at`, falling back to `created_at`.
  static DateTime? _uploadedAt(Map<String, dynamic> json) =>
      parseApiDate(json['uploaded_at']) ?? parseApiDate(json['created_at']);

  /// `https://cdn/…/Contract.pdf?sig=…` → `Contract.pdf`.
  static String? _fileNameFromUrl(String url) {
    if (url.isEmpty) return null;
    final path = url.split('?').first;
    final segment = path.split('/').last;
    return segment.isEmpty ? null : Uri.decodeComponent(segment);
  }
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
