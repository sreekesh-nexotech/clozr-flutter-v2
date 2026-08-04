/// DRF `StandardResultsSetPagination` envelope:
/// `{count, next, previous, results}` (page size default 100, max 200).
class Paginated<T> {
  const Paginated({
    required this.count,
    required this.results,
    this.next,
    this.previous,
  });

  final int count;
  final String? next;
  final String? previous;
  final List<T> results;

  bool get hasMore => next != null;

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromItem,
  ) {
    final raw = json['results'];
    final items = raw is List
        ? raw.whereType<Map<String, dynamic>>().map(fromItem).toList()
        : <T>[];
    return Paginated(
      count: (json['count'] as num?)?.toInt() ?? items.length,
      next: json['next'] as String?,
      previous: json['previous'] as String?,
      results: items,
    );
  }

  /// Some list endpoints are unpaginated (bare arrays, e.g. status-types).
  /// This normalizes either shape into a [Paginated].
  static Paginated<T> fromAny<T>(
    Object? body,
    T Function(Map<String, dynamic>) fromItem,
  ) {
    if (body is Map<String, dynamic> && body.containsKey('results')) {
      return Paginated.fromJson(body, fromItem);
    }
    if (body is List) {
      final items = body.whereType<Map<String, dynamic>>().map(fromItem).toList();
      return Paginated(count: items.length, results: items);
    }
    return Paginated(count: 0, results: <T>[]);
  }
}
