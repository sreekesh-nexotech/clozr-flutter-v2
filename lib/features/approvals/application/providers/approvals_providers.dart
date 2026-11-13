import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../../auth/domain/entities/module_access.dart';
import '../../domain/entities/approval.dart';
import '../../domain/repositories/approvals_repository.dart';
import '../../infrastructure/data_sources/local/approvals_mock_ds.dart';
import '../../infrastructure/data_sources/remote/approvals_remote_ds.dart';
import '../../infrastructure/repositories/approvals_api_repository.dart';
import '../../infrastructure/repositories/approvals_repository_impl.dart';
import '../approval_rules.dart';

/// DI seam: mock-backed in mock mode, API-backed when a base URL is set.
final approvalsRepositoryProvider = Provider<ApprovalsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return ApprovalsRepositoryImpl(const ApprovalsMockDataSource());
  }
  return ApprovalsApiRepository(
      ApprovalsRemoteDataSource(ref.watch(apiServiceProvider)));
});

/// One page of `GET /approvals/` for [ApprovalListQuery].
final approvalsListProvider = FutureProvider.autoDispose
    .family<ApprovalPage, ApprovalListQuery>(
        (ref, query) => ref.watch(approvalsRepositoryProvider).list(query));

/// One request in full — `GET /approvals/{id}/`.
final approvalDetailProvider = FutureProvider.autoDispose
    .family<ApprovalDetail, String>(
        (ref, id) => ref.watch(approvalsRepositoryProvider).detail(id));

/// How often the counts are re-read while something shows them. The server
/// caches them for 60 s per user, so asking faster only returns the same.
const approvalCountsRefresh = Duration(seconds: 60);

/// `GET /approvals/counts/` — the drawer badge, the Waiting-for-me count and
/// the "Other approvals" strip. Re-read every [approvalCountsRefresh] while
/// watched and after any write; zero on any failure, never an error.
final approvalCountsProvider =
    FutureProvider.autoDispose<ApprovalCounts>((ref) async {
  ref.watch(apiWriteTickProvider);
  final timer = Timer(approvalCountsRefresh, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    return await ref.watch(approvalsRepositoryProvider).counts();
  } on Object {
    return ApprovalCounts.zero;
  }
});

/// Whether the viewer manages anyone, or is a System Admin (`full_access`):
/// the Team tab is theirs from the start. Unknown access (mock mode, a failed
/// fetch) counts as yes — the server scopes the rows either way.
final approvalsManagesProvider = Provider.autoDispose<bool>((ref) {
  final ModuleAccess? access = ref.watch(moduleAccessProvider).valueOrNull;
  if (access == null) return true;
  return access.hasSubordinates || access.fullAccess || access.isSuperuser;
});

/// The Team-tab probe for everyone else: a Project Manager has no flag of
/// their own, so their tab appears once it has rows. 0 on any failure.
final approvalsTeamProbeProvider = FutureProvider.autoDispose<int>((ref) async {
  if (ref.watch(approvalsManagesProvider)) return 0;
  try {
    final page = await ref
        .watch(approvalsRepositoryProvider)
        .list(const ApprovalListQuery(tab: ApprovalTabs.team, pageSize: 1));
    return page.count;
  } on Object {
    return 0;
  }
});

/// The tabs this viewer sees, in order.
final approvalTabsProvider = Provider.autoDispose<List<String>>((ref) {
  final manages = ref.watch(approvalsManagesProvider);
  final probe = ref.watch(approvalsTeamProbeProvider).valueOrNull ?? 0;
  final team = showTeamTab(manages: manages, isAdmin: false, teamCount: probe);
  return [
    for (final t in ApprovalTabs.all)
      if (t != ApprovalTabs.team || team) t
  ];
});

/// One record's approval state — what waits on it, and what a save of the
/// current user's would need. `GET /approvals/for-record/`, re-read after any
/// write so a banner follows the record. [RecordApprovalState.unknown] on any
/// failure: the record page stays fully usable and the server still gates.
final recordApprovalProvider = FutureProvider.autoDispose
    .family<RecordApprovalState, ({String module, String objectId})>(
        (ref, key) async {
  if (key.objectId.isEmpty) return RecordApprovalState.unknown;
  ref.watch(apiWriteTickProvider);
  try {
    return await ref
        .watch(approvalsRepositoryProvider)
        .forRecord(key.module, key.objectId);
  } on Object {
    return RecordApprovalState.unknown;
  }
});

/// The records this session just sent for approval — the "Sent for approval"
/// chip on list and board cards. Client state on purpose: list and board rows
/// carry no approval flag yet (backend ask AP-2), so the chip lasts until the
/// request is decided here or the app restarts. A record page always reads
/// the real state from the server.
class HeldRecordsController extends StateNotifier<Set<String>> {
  HeldRecordsController() : super(const {});

  void markHeld(Iterable<String> ids) {
    final next = {...state, ...ids.where((id) => id.isNotEmpty)};
    if (next.length != state.length) state = next;
  }

  void release(String id) {
    if (!state.contains(id)) return;
    state = {...state}..remove(id);
  }

  void clear() => state = const {};
}

final heldRecordsProvider =
    StateNotifierProvider<HeldRecordsController, Set<String>>(
        (ref) => HeldRecordsController());

/// Whether this session sent [recordId] for approval.
final isRecordHeldProvider = Provider.autoDispose.family<bool, String>(
    (ref, recordId) => ref.watch(heldRecordsProvider).contains(recordId));
