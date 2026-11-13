import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_providers.dart';
import '../../infrastructure/data_sources/remote/quote_builder_remote_ds.dart';
import '../quote_builder/option_tabs.dart';
import '../quote_builder/quote_builder_draft.dart';
import '../quote_builder/quote_template_parts.dart';

/// Server data the quote builder reads — each one fetched only while the
/// builder is open (autoDispose), like the web builder's queries.

final quoteBuilderDsProvider = Provider<QuoteBuilderRemoteDataSource>(
  (ref) => QuoteBuilderRemoteDataSource(ref.watch(apiServiceProvider)),
);

/// Quote-family, active templates.
final quoteBuilderTemplatesProvider =
    FutureProvider.autoDispose<List<QuoteTemplateOption>>(
  (ref) => ref.watch(quoteBuilderDsProvider).templates(),
);

/// The tenant's "Amounts are" default and recurring-billing switch.
final quoteTaxDefaultsProvider = FutureProvider.autoDispose<QuoteTaxDefaults>(
  (ref) => ref.watch(quoteBuilderDsProvider).taxDefaults(),
);

final quoteClauseLibraryProvider =
    FutureProvider.autoDispose<List<LibraryClause>>(
  (ref) => ref.watch(quoteBuilderDsProvider).clauseLibrary(),
);

final quoteDefaultStatusProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(quoteBuilderDsProvider).defaultStatusId(),
);

/// The selected template's own (editable) fields.
final quoteTemplateFieldsProvider =
    FutureProvider.autoDispose.family<List<TemplateField>, String>(
  (ref, templateId) async => templateId.isEmpty
      ? const <TemplateField>[]
      : editableTemplateFields(
          await ref.watch(quoteBuilderDsProvider).templateFields(templateId)),
);

/// The selected template's Item Quote layout config.
final quoteTemplateConfigProvider =
    FutureProvider.autoDispose.family<TemplateLayoutConfig, String>(
  (ref, templateId) async => templateId.isEmpty
      ? const TemplateLayoutConfig()
      : ref.watch(quoteBuilderDsProvider).templateConfig(templateId),
);

/// The "Quote details" fields for a template and the party / quote.
final quoteSpotInputsProvider = FutureProvider.autoDispose.family<
    List<SpotInputField>,
    ({
      String templateId,
      String leadId,
      String customerId,
      String quotationId
    })>(
  (ref, k) => ref.watch(quoteBuilderDsProvider).spotInputs(
        k.templateId,
        leadId: k.leadId,
        customerId: k.customerId,
        quotationId: k.quotationId,
      ),
);

/// The quote being edited — always fresh from the server.
final quoteBuilderQuoteProvider =
    FutureProvider.autoDispose.family<SavedQuote, String>(
  (ref, id) => ref.watch(quoteBuilderDsProvider).fetchQuote(id),
);

/// The alternative-options group an edited option belongs to.
final quoteBuilderGroupProvider =
    FutureProvider.autoDispose.family<OptionGroupData, String>(
  (ref, id) => ref.watch(quoteBuilderDsProvider).fetchGroup(id),
);

/// The unsaved New-quote form, kept when the builder is closed with Cancel (or
/// the header back) so the next "New quote" reopens with the same title and
/// lines — the webapp's modal keeps its state the same way. The lead /
/// customer pick is not kept. Tied to the signed-in user so another account
/// never sees it; cleared after a successful create and on Discard.
///
/// An alternative-options quote keeps every option tab too: restoring only the
/// active option re-seeded tab A from whichever option was open and the other
/// options' lines were lost (UAT — a group saved with identical options).
final quoteNewDraftProvider = StateProvider<
    ({
      String userId,
      BuilderDraft draft,
      List<OptionTab>? tabs,
      int activeTab,
      int primaryTab,
    })?>((ref) => null);
