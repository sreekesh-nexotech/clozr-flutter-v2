import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/app_error.dart';
import '../../../../../core/network/network_providers.dart';
import '../../../application/providers/quote_detail_providers.dart';
import '../../../application/quote_lifecycle.dart';
import 'quote_dialogs.dart';

/// "Generate document" from a lead or customer (no quote): the quote-only
/// Proposal / Quotation templates are listed greyed with their reason. Returns true
/// once a document was generated.
Future<bool> generateDocumentForRecord(
  BuildContext context,
  WidgetRef ref, {
  String leadId = '',
  String customerId = '',
}) {
  final ds = ref.read(quoteActionsDsProvider);
  final api = ref.read(apiServiceProvider);
  Map<String, dynamic> body(DocTemplate t, Map<String, String> v) =>
      generateDocumentBodyFor(t, v, leadId: leadId, customerId: customerId);
  return showGenerateDocumentDialog(
    context,
    hasQuote: false,
    onPreview: (t, v) => ds.previewDocument(body(t, v)),
    onSubmit: (t, v) async {
      try {
        final r = await ds.generateDocument(body(t, v));
        return (
          error: null,
          fileUrl: '${r['file_url_signed'] ?? r['file_url'] ?? ''}',
          number: '${r['document_number'] ?? ''}'
        );
      } on AppError catch (e) {
        api.handled(e);
        return (error: e.bareMessage, fileUrl: '', number: '');
      }
    },
  );
}
