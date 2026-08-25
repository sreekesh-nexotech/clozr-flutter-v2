import '../entities/crm_catalog.dart';
import '../entities/quote.dart';
import '../entities/view_schema.dart';

/// Abstract contract for quote data. The presentation layer depends only on
/// this; whether quotes come from a mock source or a REST API is an
/// infrastructure detail.
abstract class QuotesRepository {
  Future<List<Quote>> getQuotes();

  /// The quotes raised against one lead — the Quotes tab on the lead detail
  /// screen. Scoped by the backend, not by filtering the org-wide list.
  Future<List<Quote>> getQuotesForLead(String leadId);

  /// The org's Quote layout, which drives the New quote form — which fields it
  /// offers, in what order, under what labels.
  ///
  /// Empty means "no opinion": mock mode, a failed fetch, or an org with no
  /// config. The form then shows its built-in field set.
  Future<ViewSchema> getQuoteSchema();

  /// The org's own quote statuses (`/quotations/statuses/`). Empty means no
  /// catalog, which callers read as "use the built-in vocabulary".
  Future<List<CatalogOption>> getQuoteStatuses();

  /// The org's quote templates for the template picker. Empty means no picker —
  /// the server then applies the org's default template on create.
  Future<List<QuoteTemplate>> getQuoteTemplates();

  /// `POST /quotations/quotations/` — creates a quote from API-shaped fields
  /// (`lead`, `payment_type`, `line_items`, …).
  ///
  /// Returns the created quote, or null when the backend response shape is
  /// unexpected. Throws on a rejected write so the form can show why.
  Future<Quote?> createQuote(Map<String, dynamic> fields);

  /// Moves a quote to another status — `PATCH .../{quotation_id}/`
  /// `{"status_id": …}`, addressed by the record's **UUID**.
  ///
  /// Throws on a rejected write: entering the org's converted status is what
  /// makes the server raise the invoice, so a failure has to reach the user
  /// rather than leaving the screen claiming a conversion that did not happen.
  Future<void> updateQuoteStatus(String quotationId, String statusId);

  /// Partially updates a quote — the detail card's inline field edits.
  /// [quotationId] is the record uuid, not the `QTN-…` display number.
  Future<void> updateQuote(String quotationId, Map<String, dynamic> fields);
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
