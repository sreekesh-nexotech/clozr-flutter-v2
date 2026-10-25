import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';

/// One record endpoint to check, plus any params its kind needs (a follow-up is
/// only found with `is_followup=true`).
class RecordProbe {
  const RecordProbe(this.path, [this.query = const {}]);

  final String path;
  final Map<String, dynamic> query;

  String get _key =>
      '$path?${(query.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join('&')}';

  @override
  bool operator ==(Object other) => other is RecordProbe && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

/// True once the server answers 404 for the record — it was deleted or moved
/// since the list that opened it was loaded.
///
/// Several detail screens paint from the already-loaded list row, so on their
/// own they keep showing a record the server no longer has. The webapp loads
/// the record and shows "<Record> not found"; this asks the same question.
/// Anything other than a 404 (offline, 5xx, 403) is not proof the record is
/// gone and resolves false, leaving the screen as it was.
final recordGoneProvider =
    FutureProvider.autoDispose.family<bool, RecordProbe>((ref, probe) async {
  if (!ApiConfig.apiEnabled || probe.path.isEmpty) return false;
  try {
    await ref.read(apiServiceProvider).get(probe.path, query: probe.query, quiet: true);
    return false;
  } on AppError catch (e) {
    return e.type == AppErrorType.notFound;
  } on Object {
    return false;
  }
});
