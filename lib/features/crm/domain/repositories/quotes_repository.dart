import '../entities/quote.dart';
import '../entities/view_schema.dart';

/// Abstract contract for quote data. The presentation layer depends only on
/// this; whether quotes come from a mock source or a REST API is an
/// infrastructure detail.
abstract class QuotesRepository {
  Future<List<Quote>> getQuotes();

  /// The org's Quote layout, which drives the New quote form — which fields it
  /// offers, in what order, under what labels.
  ///
  /// Empty means "no opinion": mock mode, a failed fetch, or an org with no
  /// config. The form then shows its built-in field set.
  Future<ViewSchema> getQuoteSchema();

  /// The org's quote templates for the template picker. Empty means no picker —
  /// the server then applies the org's default template on create.
  Future<List<QuoteTemplate>> getQuoteTemplates();

  /// `POST /quotations/quotations/` — creates a quote from API-shaped fields
  /// (`lead`, `payment_type`, `line_items`, …).
  ///
  /// Returns the created quote, or null when the backend response shape is
  /// unexpected. Throws on a rejected write so the form can show why.
  Future<Quote?> createQuote(Map<String, dynamic> fields);
}

/// One selectable quote template.
class QuoteTemplate {
  const QuoteTemplate({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final bool isDefault;
}
