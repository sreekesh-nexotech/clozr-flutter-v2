import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/quote.dart';
import '../../domain/repositories/quotes_repository.dart';
import '../data_sources/remote/quotes_remote_ds.dart';

/// API-backed [QuotesRepository]: remote fetch with Hive fallback when the
/// network is down (guide §2: cache raw rows, map on read).
class QuotesApiRepository implements QuotesRepository {
  const QuotesApiRepository(this._remote);

  final QuotesRemoteDataSource _remote;

  static const String _cacheKey = 'quotes';

  @override
  Future<List<Quote>> getQuotes() async {
    try {
      final rows = await _remote.fetchQuoteRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return quotesFromApiRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(AppCache.crmCache, _cacheKey);
        final data = cached?.data;
        if (data is List) return quotesFromApiRows(data);
      }
      rethrow;
    }
  }
}
