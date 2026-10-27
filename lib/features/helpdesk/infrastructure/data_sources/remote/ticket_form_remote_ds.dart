import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../application/ticket_form_rules.dart';

/// One picker row: the id the write sends and the label shown.
typedef TicketPickOption = ({String id, String name});

/// The pickers behind New / Edit Ticket — the webapp's `useHelpdeskPickers`,
/// `useIssueContacts`, `useCustomerSlaQuery` and `useTicketBillingDefaults`.
///
/// Every read is [ApiService.get] `quiet`: the form renders the refusal in
/// place ("You don't have permission to view customers."), so the shell's
/// generic toast must not repeat it.
class TicketFormRemoteDataSource {
  const TicketFormRemoteDataSource(this._api);

  final ApiService _api;

  /// Rows per customer search page — enough to scan, small enough to stay fast.
  static const customerPageSize = 20;

  /// `GET customers/?search=&page_size=20` — searched server-side (name,
  /// email, phone, …); an empty [search] asks for the first page. Answers the
  /// page and the server-wide total. Throws the [AppError] on failure.
  Future<(List<TicketPickOption>, int)> searchCustomers(String search) async {
    final q = search.trim();
    final body = await _api.get(ApiEndpoints.customers, quiet: true, query: {
      'page_size': customerPageSize,
      'fields': 'customer_id,name',
      if (q.isNotEmpty) 'search': q,
    });
    final page = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
    final out = <TicketPickOption>[];
    for (final r in page.results) {
      final id = (r['customer_id'] ?? '').toString();
      if (id.isEmpty) continue;
      final name = (r['name'] ?? '').toString().trim();
      out.add((id: id, name: name.isEmpty ? 'Unnamed customer' : name));
    }
    return (out, page.count < out.length ? out.length : page.count);
  }

  /// `GET contacts/?customer_id=` — the Contact select's options.
  Future<List<TicketPickOption>> fetchContacts(String customerId) async {
    final body = await _api.get(ApiEndpoints.contacts, quiet: true, query: {'customer_id': customerId});
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    final out = <TicketPickOption>[];
    for (final r in rows) {
      final id = (r['contact_id'] ?? '').toString();
      if (id.isEmpty) continue;
      final parts = [r['first_name'], r['last_name']].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      final name = [r['display_name'], r['full_name'], parts, r['email']]
          .whereType<String>()
          .firstWhere((s) => s.trim().isNotEmpty, orElse: () => 'Unnamed contact');
      out.add((id: id, name: name));
    }
    return out;
  }

  /// The picked customer's SLA for the "Resolve by" preview — off the
  /// customer **detail** (the list never carries the SLA). Null when unreadable.
  Future<CustomerSla?> fetchCustomerSla(String customerId) async {
    try {
      final body = await _api.get(ApiEndpoints.customer(customerId),
          quiet: true, query: {'fields': 'customer_id,sla_value,sla_unit'});
      return body is Map<String, dynamic> ? customerSlaFrom(body) : null;
    } on Object {
      return null;
    }
  }

  /// `GET management/assignable-users/?module=issue` — only users who can
  /// read tickets; the save refuses anyone else (`assignee_no_module_access`).
  Future<List<TicketPickOption>> fetchAssignableUsers() async {
    final body = await _api.get(ApiEndpoints.assignableUsers,
        quiet: true, query: {'module': 'issue', 'page_size': 200});
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    final out = <TicketPickOption>[];
    for (final r in rows) {
      final id = (r['user_id'] ?? r['id'] ?? '').toString();
      if (id.isEmpty || r['is_active'] == false) continue;
      final name = (r['full_name'] ?? '').toString().trim();
      out.add((id: id, name: name.isNotEmpty ? name : (r['email'] ?? 'User').toString()));
    }
    return out;
  }

  /// `GET issues/billing-defaults/` — null when unavailable (the label then
  /// stays neutral: "Billable amount (₹)").
  Future<TicketBillingDefaults?> fetchBillingDefaults() async {
    try {
      return ticketBillingDefaultsFrom(await _api.get(ApiEndpoints.issueBillingDefaults, quiet: true));
    } on Object {
      return null;
    }
  }
}
