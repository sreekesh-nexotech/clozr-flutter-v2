import '../../../../app/config/constants.dart';
import '../../domain/entities/quote.dart';
import '../../domain/repositories/quotes_repository.dart';
import '../data_sources/local/quotes_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class QuotesRepositoryImpl implements QuotesRepository {
  const QuotesRepositoryImpl(this._local);

  final QuotesMockDataSource _local;

  @override
  Future<List<Quote>> getQuotes() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchQuotes();
  }
}
