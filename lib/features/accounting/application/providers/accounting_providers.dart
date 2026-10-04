import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../../../core/auth/session_gate.dart';
import '../../../auth/domain/entities/module_access.dart';
import '../../domain/entities/acc_masters.dart';
import '../../domain/entities/acc_setup.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../infrastructure/data_sources/remote/accounting_documents_remote_ds.dart';
import '../../infrastructure/data_sources/remote/accounting_masters_remote_ds.dart';
import '../../infrastructure/data_sources/remote/accounting_reports_remote_ds.dart';
import '../../infrastructure/data_sources/remote/accounting_settlement_remote_ds.dart';
import '../../infrastructure/repositories/accounting_api_repository.dart';

/// The seven accounting permission areas (handover §3).
const accModules = [
  'acc_setup',
  'acc_document',
  'acc_purchase',
  'acc_settlement',
  'acc_period',
  'acc_journal',
  'acc_report',
];

final accountingRepositoryProvider = Provider<AccountingRepository>((ref) {
  final api = ref.watch(apiServiceProvider);
  return AccountingApiRepository(
    documentsDs: AccountingDocumentsRemoteDataSource(api),
    mastersDs: AccountingMastersRemoteDataSource(api),
    settlementDs: AccountingSettlementRemoteDataSource(api),
    reportsDs: AccountingReportsRemoteDataSource(api),
  );
});

/// `GET /billing/features/me/` — the plan features that are switched on.
///
/// Null means "unknown, don't gate": mock mode, not signed in, or a failed
/// fetch — the same fail-open rule as `moduleAccessProvider`. The backend
/// enforces the plan on every request regardless of what the menu shows.
final planFeaturesProvider = FutureProvider<Set<String>?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  if (ref.watch(sessionControllerProvider).status != SessionStatus.authenticated) return null;
  try {
    return await ref.watch(accountingRepositoryProvider).myFeatures();
  } on Object {
    return null;
  }
});

/// Where the organisation stands with accounting (handover §2), resolved from
/// three pre-checks in order — permissions, plan, activation — never from an
/// error body.
///
/// A user without `acc_setup` cannot read the tenant profile, so for them the
/// activation answer comes from one cheap read against a module they *can*
/// see: `ACCOUNTING_NOT_ACTIVE` means inactive, a normal answer means active.
final accountingStatusProvider = FutureProvider<AccountingStatus>((ref) async {
  if (!ApiConfig.apiEnabled) return AccountingStatus.unavailable;
  if (ref.watch(sessionControllerProvider).status != SessionStatus.authenticated) {
    return AccountingStatus.unknown;
  }
  final access = await ref.watch(moduleAccessProvider.future);
  if (access != null && !access.canAny(accModules)) return AccountingStatus.noAccess;

  final features = await ref.watch(planFeaturesProvider.future);
  if (features != null && !features.contains('accounting')) return AccountingStatus.notInPlan;

  final repo = ref.watch(accountingRepositoryProvider);
  if (access == null || access.can('acc_setup')) {
    try {
      final profile = await repo.tenantProfile();
      return _fromActivation(profile?.activationStatus);
    } on AppError catch (e) {
      // Unknown access (a failed modules fetch) is the one case a 403 here is
      // not final — fall through to the probe with whatever can be read.
      if (!(access == null && e.type == AppErrorType.forbidden)) rethrow;
    }
  }
  final path = _probePath(access);
  if (path == null) return AccountingStatus.noAccess;
  return await repo.probeActive(path) ? AccountingStatus.active : AccountingStatus.inactive;
});

AccountingStatus _fromActivation(String? s) => switch (s) {
      'ACTIVE' => AccountingStatus.active,
      'ACTIVATING' || 'SUSPENDED' => AccountingStatus.paused,
      _ => AccountingStatus.inactive,
    };

/// A one-row read against the first accounting area this user can see.
String? _probePath(ModuleAccess? access) {
  bool can(String k) => access == null || access.can(k);
  if (can('acc_document')) return ApiEndpoints.accDocuments;
  if (can('acc_settlement')) return ApiEndpoints.accReceipts;
  if (can('acc_purchase')) return ApiEndpoints.accVendors;
  if (can('acc_period')) return ApiEndpoints.accFiscalYears;
  if (can('acc_journal')) return ApiEndpoints.accLedgerEvents;
  if (can('acc_report')) return ApiEndpoints.accArAging;
  return null;
}

/// True only once accounting is known to be open for posting. CRM screens read
/// this to decide whether to show accounting affordances at all (tax profile,
/// Issue invoice, Bill ticket, financials) — never true in mock mode.
final accountingActiveProvider = Provider<bool>(
  (ref) => ref.watch(accountingStatusProvider).valueOrNull == AccountingStatus.active,
);

/// One accounting module's verbs for the signed-in user.
///
/// Fail-open like the drawer: while access is unknown every verb reads true
/// and the backend's 403 is the answer. Superusers and staff with
/// `full_access` get everything; note money-posting endpoints no longer honour
/// `is_staff` alone (handover §3), which the server enforces.
class AccPerm {
  const AccPerm({this.read = true, this.create = true, this.update = true, this.delete = true, this.approve = true});

  static const open = AccPerm();
  static const none = AccPerm(read: false, create: false, update: false, delete: false, approve: false);

  final bool read;
  final bool create;
  final bool update;
  final bool delete;

  /// On `acc_document` this means issue and cancel.
  final bool approve;

  factory AccPerm.of(ModulePermission? p) => p == null
      ? none
      : AccPerm(
          read: p.canRead || p.canCreate || p.canUpdate || p.canApprove,
          create: p.canCreate,
          update: p.canUpdate,
          delete: p.canDelete,
          approve: p.canApprove,
        );
}

final accPermProvider = Provider.family<AccPerm, String>((ref, module) {
  final access = ref.watch(moduleAccessProvider).valueOrNull;
  if (access == null || access.isSuperuser) return AccPerm.open;
  final base = access.fullAccess ? AccPerm.open : AccPerm.of(access.modules[module]);
  // The posting verbs come from `money_posting` when the backend sends it:
  // staff with full access are refused money-posting endpoints unless they
  // hold the seeded codename, so "full access" must not light up a button
  // that the server will 403.
  final posting = access.moneyPostingBypass ? null : access.moneyPosting[module];
  if (posting == null) return base;
  return AccPerm(
    read: base.read,
    create: base.create && (posting['can_create'] ?? base.create),
    update: base.update && (posting['can_update'] ?? base.update),
    delete: base.delete,
    approve: base.approve && (posting['can_approve'] ?? base.approve),
  );
});

/// GST state codes, cached for the session.
final gstStatesProvider = FutureProvider<List<GstState>>((ref) async {
  if (!ApiConfig.apiEnabled) return const [];
  return ref.watch(accountingRepositoryProvider).states();
});

/// `code → name` over [gstStatesProvider]; empty until it lands.
final gstStateNameProvider = Provider<String Function(String?)>((ref) {
  final states = ref.watch(gstStatesProvider).valueOrNull ?? const [];
  final byCode = {for (final s in states) s.code: s.name};
  return (code) => code == null ? '—' : (byCode[code] == null ? code : '${byCode[code]} ($code)');
});

/// The org's active bank / cash / gateway accounts, default first.
final bankAccountsProvider = FutureProvider.autoDispose<List<BankAccount>>(
  (ref) => ref.watch(accountingRepositoryProvider).bankAccounts(),
);

/// The tenant profile, for the Status screen and for form defaults
/// (`default_amounts_are`). Null when never created, or when this user cannot
/// read setup — callers treat null as "no defaults".
final tenantProfileProvider = FutureProvider<TenantProfile?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  if (!ref.watch(accPermProvider('acc_setup')).read) return null;
  try {
    return await ref.watch(accountingRepositoryProvider).tenantProfile();
  } on AppError {
    return null;
  }
});
