import '../entities/quote.dart';

/// Abstract contract for quote data. The presentation layer depends only on
/// this; whether quotes come from a mock source or a REST API is an
/// infrastructure detail.
abstract class QuotesRepository {
  Future<List<Quote>> getQuotes();
}
