import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/paginated.dart';

/// One server-side search: which list endpoint to ask, which keys carry the
/// row ids the screen matches on, any scope params that list always sends, and
/// the query itself.
///
/// The webapp sends the box's text as `?search=` and lets the server match it
/// across every searchable column — email, phone, description, location,
/// lead/customer names on quotes, and so on. The mobile lists hold rows that
/// carry only the card's fields, so a local substring match could never find a
/// lead by its email. This key asks the server the same question the webapp
/// does and gets back the ids that match.
class ServerSearchKey {
  const ServerSearchKey({
    required this.endpoint,
    required this.idFields,
    required this.query,
    this.scope = const {},
  });

  final String endpoint;
  final List<String> idFields;
  final String query;
  final Map<String, dynamic> scope;

  String get _scopeKey =>
      (scope.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join('&');

  @override
  bool operator ==(Object other) =>
      other is ServerSearchKey &&
      other.endpoint == endpoint &&
      other.query == query &&
      other.idFields.join(',') == idFields.join(',') &&
      other._scopeKey == _scopeKey;

  @override
  int get hashCode => Object.hash(endpoint, query, idFields.join(','), _scopeKey);
}

/// Ids of the rows the server says match [ServerSearchKey.query], or null while
/// there is nothing to ask (blank query, mock mode) or the answer is pending.
///
/// Debounced 350 ms like the webapp's box: each keystroke builds a new key, the
/// previous one is disposed, and only a query left alone that long hits the
/// network. Failures resolve to null so the list falls back to its local match
/// instead of emptying.
final serverSearchIdsProvider =
    FutureProvider.autoDispose.family<Set<String>?, ServerSearchKey>((ref, key) async {
  final q = key.query.trim();
  if (q.isEmpty || !ApiConfig.apiEnabled) return null;
  var disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (disposed) return null;

  final api = ref.read(apiServiceProvider);
  final ids = <String>{};
  try {
    for (var page = 1; page <= 5; page++) {
      final body = await api.get(key.endpoint, quiet: true, query: {
        ...key.scope,
        'search': q,
        'page_size': 200,
        'page': page,
      });
      if (disposed) return null;
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (row) => row);
      for (final row in paged.results) {
        for (final f in key.idFields) {
          final v = row[f];
          if (v != null && '$v'.isNotEmpty) ids.add('$v');
        }
      }
      if (!paged.hasMore) break;
    }
  } on Object {
    return null;
  }
  return ids;
});

/// Watches the server answer for [key] and returns a predicate for the list:
/// a row is kept when the local [localMatch] finds it (instant, while typing)
/// or the server listed one of its [ids].
bool Function(Iterable<String?> ids, bool localMatch) serverSearchMatcher(
  Ref ref,
  ServerSearchKey key,
) {
  final hits = key.query.trim().isEmpty
      ? null
      : ref.watch(serverSearchIdsProvider(key)).valueOrNull;
  return (ids, localMatch) {
    if (localMatch) return true;
    if (hits == null) return false;
    for (final id in ids) {
      if (id != null && hits.contains(id)) return true;
    }
    return false;
  };
}
