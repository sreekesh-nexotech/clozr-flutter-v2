import '../../../../core/network/app_error.dart';
import '../../domain/entities/reward.dart';
import '../../domain/repositories/rewards_repository.dart';
import '../data_sources/remote/rewards_remote_ds.dart';

/// API-backed [RewardsRepository].
///
/// Caching is intentionally skipped for this slice (no dedicated AppCache box
/// exists; the load-then-notify provider surfaces an error phase on failure).
/// Grants are a best-effort enrichment: visibility rules can 403 the
/// `/milestones/rewards/` list without sinking the whole bundle.
class RewardsApiRepository implements RewardsRepository {
  RewardsApiRepository(this._remote);

  final RewardsRemoteDataSource _remote;

  @override
  Future<RewardsData> getRewards() async {
    // The enrichment base is an EMPTY bundle (never the mock): every field the
    // two milestone endpoints cannot provide stays honestly empty (audit
    // L-3 / M2), so no mock data can leak into API mode.
    final base = RewardsData.empty();
    final progressRows = await _remote.fetchProgressRows();
    List<Map<String, dynamic>> grantRows = const [];
    try {
      grantRows = await _remote.fetchGrantRows();
    } on AppError {
      // Not readable for this user — goals simply keep generic reward copy.
    }
    return RewardsRemoteDataSource.mapRewards(
      base: base,
      progressRows: progressRows,
      grantRows: grantRows,
    );
  }
}
