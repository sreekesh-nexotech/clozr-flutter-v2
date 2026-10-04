import '../../../../../core/network/paginated.dart';
import '../../../domain/entities/acc_settlement.dart';

/// Small helpers shared by the accounting data sources.

/// The rows and paging of one list page, left raw so a repository can cache
/// exactly what the server sent.
class RawPage {
  const RawPage(this.rows, {this.count = 0, this.hasMore = false});

  final List<Map<String, dynamic>> rows;
  final int count;
  final bool hasMore;

  static RawPage from(Object? body) {
    final p = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
    return RawPage(p.results, count: p.count, hasMore: p.hasMore);
  }

  Map<String, dynamic> toJson() => {'results': rows, 'count': count, 'has_more': hasMore};

  static RawPage fromCache(Object? data) {
    if (data is! Map) return const RawPage([]);
    final rows = [
      for (final r in (data['results'] as List? ?? const []))
        if (r is Map) Map<String, dynamic>.from(r),
    ];
    return RawPage(rows,
        count: (data['count'] as num?)?.toInt() ?? rows.length,
        hasMore: data['has_more'] == true);
  }
}

/// Drops null / blank values from a query or body, and never sends an empty
/// string — the report endpoints 500 on one (handover §12.6).
Map<String, dynamic> compact(Map<String, Object?> m) => {
      for (final e in m.entries)
        if (e.value != null && !(e.value is String && (e.value as String).trim().isEmpty))
          e.key: e.value,
    };

/// Wraps a posting response: `200 {skipped: true}` is its own outcome.
PostOutcome<T> postOutcome<T>(Object? body, T? Function(Map<String, dynamic>) map) {
  if (body is Map && body['skipped'] == true) {
    return PostOutcome<T>.skipped(body['detail'] is String ? body['detail'] as String : null);
  }
  final value = body is Map ? map(Map<String, dynamic>.from(body)) : null;
  return PostOutcome<T>.posted(value);
}
