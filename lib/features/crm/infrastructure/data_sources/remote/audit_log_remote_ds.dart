import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../domain/entities/audit_entry.dart';

/// A record's activity log: `GET /access-control/audit-logs/`.
///
/// Shared across modules — the same endpoint backs the Lead, Customer and
/// Quotation activity cards, differing only by `model_name` + `record_id`.
///
/// **This endpoint returns raw diffs.** Unlike the project/task activity feeds,
/// it sends no `summary` or `event_type`, so the humanizing here is not
/// decoration — without it there is nothing renderable, just before/after field
/// dumps.
///
/// Best-effort: any failure yields an empty list. Reading the audit trail needs
/// the `view_audit_log` permission, so a perfectly ordinary user gets a 403 —
/// that must not break the page they came for.
class AuditLogRemoteDataSource {
  const AuditLogRemoteDataSource(this._api);

  final ApiService _api;

  /// Newest-first, capped — an activity card shows a recent history, not the
  /// record's entire life.
  static const int _pageSize = 30;

  Future<List<AuditEntry>> fetchFor({
    required String modelName,
    required String recordId,
    Map<String, String> statusNames = const {},
  }) async {
    if (recordId.isEmpty) return const [];
    try {
      final body = await _api.get(ApiEndpoints.auditLogs, query: {
        'model_name': modelName,
        'record_id': recordId,
        'ordering': '-timestamp',
        'page_size': _pageSize,
      });
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      return mapEntries(rows, statusNames: statusNames);
    } on Object {
      return const [];
    }
  }

  // ── mapping (visible for tests) ──

  static List<AuditEntry> mapEntries(
    List<dynamic> rows, {
    Map<String, String> statusNames = const {},
  }) {
    final out = <AuditEntry>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final entry = mapEntry(row, statusNames: statusNames);
      if (entry != null) out.add(entry);
    }
    return out;
  }

  /// Turns one raw audit row into a readable timeline entry, or null when the
  /// row describes nothing worth showing.
  ///
  /// [statusNames] maps `lead_status_id` → name so a stage change reads
  /// "Status changed to Qualified" rather than quoting a uuid at the user.
  static AuditEntry? mapEntry(
    Map<String, dynamic> row, {
    Map<String, String> statusNames = const {},
  }) {
    final id = _str(row['audit_log_id']);
    if (id.isEmpty) return null;

    final action = _str(row['action']).toLowerCase();
    final actor = _str(row['user_full_name']);
    final at = parseApiDate(row['timestamp']);
    final changes = row['changes'];

    AuditEntry build(AuditEventKind kind, String title, [String subtitle = '']) =>
        AuditEntry(id: id, kind: kind, title: title, subtitle: subtitle, at: at, actor: actor);

    if (action == 'create') {
      return build(AuditEventKind.created, 'Lead created', _by(actor));
    }
    if (action == 'delete') {
      return build(AuditEventKind.deleted, 'Deleted', _by(actor));
    }

    if (changes is Map) {
      // A write on a child record (a note, an attachment) rolled up onto this
      // one. Carries no label here — unlike the project feed — so the type is
      // all there is to say.
      final related = changes['related_change'];
      if (related is Map) {
        final type = _str(related['type']);
        final childAction = _str(related['action']).toLowerCase();
        final label = _childLabel(type, childAction);
        return build(
          type.toLowerCase() == 'note' ? AuditEventKind.noteAdded : AuditEventKind.childAdded,
          label,
          _by(actor),
        );
      }

      // A direct field write. `request_body` is what the client sent, which is
      // a far better description of intent than diffing the whole record.
      final requested = changes['request_body'];
      if (requested is Map && requested.isNotEmpty) {
        final keys = requested.keys.map((k) => '$k').toList();

        // The stage change is the one everybody reads this log for, so it gets
        // its own sentence.
        if (keys.length == 1 && (keys.first == 'status_id' || keys.first == 'status')) {
          final toId = '${requested[keys.first]}';
          final toName = statusNames[toId];
          final before = changes['before'];
          final fromName = before is Map ? statusNames['${before['status_id']}'] : null;
          return build(
            AuditEventKind.statusChanged,
            toName == null ? 'Status changed' : 'Status changed to $toName',
            fromName == null ? _by(actor) : 'From $fromName${_bySuffix(actor)}',
          );
        }

        return build(
          AuditEventKind.fieldChanged,
          keys.length == 1
              ? '${_fieldLabel(keys.first)} updated'
              : '${keys.length} fields updated',
          keys.length == 1
              ? _by(actor)
              : '${keys.map(_fieldLabel).join(', ')}${_bySuffix(actor)}',
        );
      }
    }

    return build(AuditEventKind.other, 'Record updated', _by(actor));
  }

  static String _childLabel(String type, String action) {
    final noun = type.isEmpty ? 'Record' : type;
    switch (action) {
      case 'create':
        return noun.toLowerCase() == 'note' ? 'Note added' : '$noun added';
      case 'delete':
        return '$noun removed';
      default:
        return '$noun updated';
    }
  }

  /// `lead_owner_id` → "Lead owner"; `status_id` → "Status".
  static String _fieldLabel(String key) {
    var k = key;
    if (k.endsWith('_id')) k = k.substring(0, k.length - 3);
    k = k.replaceAll('_', ' ').trim();
    if (k.isEmpty) return key;
    return '${k[0].toUpperCase()}${k.substring(1)}';
  }

  static String _by(String actor) => actor.isEmpty ? '' : 'by $actor';

  static String _bySuffix(String actor) => actor.isEmpty ? '' : ' · by $actor';

  static String _str(Object? v) => v is String ? v : '';
}
