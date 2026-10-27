import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/paginated.dart';
import 'package:intl/intl.dart';
import '../../../../data/api/user_directory.dart';
import '../../../crm/domain/entities/crm_catalog.dart';

/// The people a project's manager / assignees may be — webapp
/// `useAssignableUsersQuery('project')`, `GET /management/assignable-users/?module=project`.
///
/// Only users who can read projects: anyone else is refused by the server
/// (`400 assignee_no_module_access`), so the picker never offers them. Ids are
/// the app's mapped user ids (`'me'` for the signed-in user), the same form the
/// roster and the write builder use. Null while loading or when the call fails
/// — the form then falls back to the roster rather than showing nobody.
final projectAssignableUsersProvider =
    FutureProvider.autoDispose<List<CatalogOption>?>(
        (ref) => ref.watch(opsAssignableUsersProvider('project').future));

/// The same list for any Operations module — `project_task` is the Add task
/// form's "Assign to" (webapp `useAssignableUsersQuery('project_task')`).
final opsAssignableUsersProvider =
    FutureProvider.autoDispose.family<List<CatalogOption>?, String>((ref, module) async {
  if (!ApiConfig.apiEnabled) return null;
  try {
    final body = await ref.watch(apiServiceProvider).get(
      '/management/assignable-users/',
      query: {'module': module, 'page_size': 200},
      quiet: true,
    );
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    final out = <CatalogOption>[];
    for (final r in rows) {
      final raw = (r['user_id'] ?? '').toString();
      if (raw.isEmpty || r['is_active'] == false) continue;
      UserDirectory.registerJson(r);
      final full = (r['full_name'] ?? '').toString().trim();
      final name = full.isNotEmpty
          ? full
          : [r['first_name'], r['last_name']]
              .where((v) => '${v ?? ''}'.trim().isNotEmpty)
              .join(' ')
              .ifEmpty('${r['email'] ?? ''}');
      out.add(CatalogOption(id: UserDirectory.mapUserId(raw), name: name));
    }
    return out;
  } on Object {
    return null;
  }
});

/// The org's "Default visibility for new projects" (PMO settings), lowercase
/// (`private` / `team` / `organization`), or null when it cannot be read — the
/// endpoint refuses roles without Settings, and those users are offered
/// "Default (set by your admin)" instead, exactly as on the webapp (UAT D32).
final pmoDefaultVisibilityProvider = FutureProvider.autoDispose<String?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  try {
    final body = await ref
        .watch(apiServiceProvider)
        .get('/settings/pmo/settings/', quiet: true);
    if (body is! Map) return null;
    final v = '${body['default_project_visibility'] ?? ''}'.trim().toLowerCase();
    return const {'private', 'team', 'organization'}.contains(v) ? v : null;
  } on Object {
    return null;
  }
});

/// The PMO "Default priority for new tasks" as the Title-Case value a task
/// carries (`High` / `Medium` / `Low`), or null when it cannot be read — the
/// settings endpoint refuses roles without Settings, and the Add task form
/// then starts on "Default (set by your admin)" (webapp `taskPriorityDefault`).
final pmoDefaultTaskPriorityProvider = FutureProvider.autoDispose<String?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  try {
    final body = await ref
        .watch(apiServiceProvider)
        .get('/settings/pmo/settings/', quiet: true);
    if (body is! Map) return null;
    return switch ('${body['default_task_priority'] ?? ''}'.trim().toLowerCase()) {
      'low' => 'Low',
      'medium' => 'Medium',
      'high' => 'High',
      _ => null,
    };
  } on Object {
    return null;
  }
});

/// One customer's quotes for the project form's "Linked quote" — webapp
/// `useCustomerQuotesQuery`: `GET /quotations/quotations/?customer_id=…`
/// (one page of 100, newest first). Labelled "QTN-number · title · ₹total".
final customerQuotesProvider = FutureProvider.autoDispose
    .family<List<CatalogOption>, String>((ref, customerId) async {
  if (!ApiConfig.apiEnabled || customerId.isEmpty) return const [];
  try {
    final body = await ref.watch(apiServiceProvider).get(
      '/quotations/quotations/',
      query: {
        'customer_id': customerId,
        'page_size': 100,
        'ordering': '-created_at',
      },
      quiet: true,
    );
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    return [
      for (final q in rows)
        if ('${q['quotation_id'] ?? ''}'.isNotEmpty)
          CatalogOption(
            id: '${q['quotation_id']}',
            name: [
              '${q['quotation_number'] ?? ''}'.trim().ifEmpty('${q['quotation_id']}'),
              if ('${q['quotation_title'] ?? ''}'.trim().isNotEmpty)
                '${q['quotation_title']}'.trim(),
              _inr.format(num.tryParse('${q['grand_total'] ?? q['total_amount'] ?? 0}') ?? 0),
            ].join(' · '),
          ),
    ];
  } on Object {
    return const [];
  }
});

/// The webapp's `money()` — full en-IN grouping, "₹3,94,758".
final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// The org's teams for the project form and the Team filter — webapp
/// `useProjectTeamsQuery` (`GET /management/teams/?page_size=100`). A quiet
/// read: roles without Teams access (403) get just "— No team —", with no
/// error toast, as on the webapp.
final projectTeamsProvider = FutureProvider<List<CatalogOption>>((ref) async {
  if (!ApiConfig.apiEnabled) return const [];
  try {
    final body = await ref
        .watch(apiServiceProvider)
        .get('/management/teams/', query: {'page_size': 100}, quiet: true);
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    return [
      for (final r in rows)
        if ('${r['team_id'] ?? ''}'.isNotEmpty)
          CatalogOption(id: '${r['team_id']}', name: '${r['name'] ?? ''}'),
    ];
  } on Object {
    return const [];
  }
});
