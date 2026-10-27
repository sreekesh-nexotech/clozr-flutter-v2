import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../data/api/roster.dart';
import '../../infrastructure/data_sources/remote/ticket_form_remote_ds.dart';
import '../ticket_form_rules.dart';
import 'tickets_providers.dart';

final ticketFormRemoteProvider =
    Provider<TicketFormRemoteDataSource>((ref) => TicketFormRemoteDataSource(ref.watch(apiServiceProvider)));

/// One page of the customer search for the (debounced, trimmed) text — the
/// page and the server-wide total. Mock mode searches the local directory.
final ticketCustomerSearchProvider =
    FutureProvider.autoDispose.family<(List<TicketPickOption>, int), String>((ref, search) async {
  if (!ApiConfig.apiEnabled) {
    final q = search.trim().toLowerCase();
    final all = [
      for (final c in ref.watch(ticketDirectoryProvider).customers.values)
        (id: c.id, name: c.company.isNotEmpty ? c.company : c.name),
    ].where((c) => q.isEmpty || c.name.toLowerCase().contains(q)).toList();
    return (all, all.length);
  }
  return ref.watch(ticketFormRemoteProvider).searchCustomers(search);
});

/// A customer's contacts for the Contact select. Empty in mock mode.
final ticketContactsProvider =
    FutureProvider.autoDispose.family<List<TicketPickOption>, String>((ref, customerId) async {
  if (!ApiConfig.apiEnabled) return const [];
  return ref.watch(ticketFormRemoteProvider).fetchContacts(customerId);
});

/// The customer's SLA terms for the SLA box; null when unknown.
final ticketCustomerSlaProvider =
    FutureProvider.autoDispose.family<CustomerSla?, String>((ref, customerId) async {
  if (!ApiConfig.apiEnabled) return null;
  return ref.watch(ticketFormRemoteProvider).fetchCustomerSla(customerId);
});

/// Who a ticket may be assigned to. Mock mode offers the local roster.
final ticketAssignableUsersProvider = FutureProvider.autoDispose<List<TicketPickOption>>((ref) async {
  if (!ApiConfig.apiEnabled) {
    return [for (final r in ref.watch(rosterProvider)) (id: r.id, name: r.name)];
  }
  return ref.watch(ticketFormRemoteProvider).fetchAssignableUsers();
});

/// The billable amount's GST basis; fetched only once billing is switched on.
final ticketBillingDefaultsProvider = FutureProvider.autoDispose<TicketBillingDefaults?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  return ref.watch(ticketFormRemoteProvider).fetchBillingDefaults();
});
