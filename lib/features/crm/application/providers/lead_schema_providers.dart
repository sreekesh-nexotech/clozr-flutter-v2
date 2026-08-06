import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/lead_schema.dart';
import '../../infrastructure/data_sources/remote/lead_schema_remote_ds.dart';

/// The org's configured Leads layout, driving what the list card renders.
///
/// Same contract as the CRM catalogs: **empty is the fallback**, not an error.
/// Mock mode, a failed fetch, and an org with no config all resolve to
/// [LeadListSchema.empty], which every consumer reads as "use the built-in
/// layout" — so the screen keeps working without the schema call.

/// Null in mock mode, which is what makes the schema resolve empty there.
final leadSchemaRemoteDataSourceProvider =
    Provider<LeadSchemaRemoteDataSource?>((ref) {
  if (!ApiConfig.apiEnabled) return null;
  return LeadSchemaRemoteDataSource(ref.watch(apiServiceProvider));
});

/// `GET /crm/leads/schema/` — fetched once per org, not per list refresh: the
/// layout changes when an admin edits it, not when leads change. Deliberately
/// independent of the My/All scope, which affects rows, never columns.
final leadListSchemaFutureProvider = FutureProvider<LeadListSchema>((ref) async {
  final ds = ref.watch(leadSchemaRemoteDataSourceProvider);
  return ds == null ? LeadListSchema.empty : ds.fetchListSchema();
});

/// Synchronous view of [leadListSchemaFutureProvider] — empty while in flight,
/// so the list renders immediately with the built-in layout and adopts the
/// org's one when it arrives, rather than holding the rows behind a spinner.
final leadListSchemaProvider = Provider<LeadListSchema>(
  (ref) => ref.watch(leadListSchemaFutureProvider).valueOrNull ?? LeadListSchema.empty,
);
