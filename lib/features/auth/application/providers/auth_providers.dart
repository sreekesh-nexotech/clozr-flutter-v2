import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_gate.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/storage/app_cache.dart';
import '../../../../data/api/user_directory.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../infrastructure/data_sources/remote/auth_remote_ds.dart';
import '../../infrastructure/repositories/auth_api_repository.dart';

/// DI seam for the auth contract.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthApiRepository(
    AuthRemoteDataSource(ref.watch(apiServiceProvider)),
  ),
);

/// Immutable session snapshot the app watches.
class SessionState {
  const SessionState({
    this.status = SessionStatus.restoring,
    this.user,
  });

  final SessionStatus status;
  final SessionUser? user;

  bool get isAuthenticated => status == SessionStatus.authenticated;

  SessionState copyWith({SessionStatus? status, SessionUser? user}) =>
      SessionState(status: status ?? this.status, user: user ?? this.user);
}

/// Owns the auth lifecycle: startup restore, the login/2FA flow, token
/// adoption, logout, and the forced logout fired by the 401 interceptor.
/// Mirrors every status change into [SessionGate] for the router.
class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref) : super(const SessionState()) {
    _init();
  }

  final Ref _ref;

  static const _userCacheKey = 'session_user';

  /// Re-entrancy guard so a burst of concurrent 401s triggers exactly one
  /// teardown instead of N cache-clears / state churn.
  bool _tearingDown = false;

  AuthRepository get _repo => _ref.read(authRepositoryProvider);

  Future<void> _init() async {
    if (!ApiConfig.apiEnabled) {
      // Mock mode has no login gate — the app boots straight into the shell.
      _set(SessionStatus.authenticated);
      return;
    }

    // Keep the 401 → forceLogout hook wired to the *current* ApiService, even
    // after it is rebuilt by a session-change invalidation. fireImmediately
    // wires the instance that exists right now.
    _ref.listen<ApiService>(
      apiServiceProvider,
      (_, next) => next.onSessionExpired = forceLogout,
      fireImmediately: true,
    );

    final tokens = _ref.read(tokenStorageProvider);
    try {
      await tokens.init();
    } on Object {
      // A keychain/keystore read failure must fail closed to the login screen,
      // never leave the gate stuck on `restoring`.
      _set(SessionStatus.unauthenticated);
      return;
    }

    if (!tokens.hasSession) {
      _set(SessionStatus.unauthenticated);
      return;
    }

    final cached = _cachedUser();
    if (cached != null) {
      // Cached profile → adopt identity (sets `currentUserId` so `isMine`/`me`
      // resolve correctly) and open the app immediately; refresh in background.
      _adoptUser(cached);
      _set(SessionStatus.authenticated);
      _refreshProfileInBackground();
    } else {
      // No cached profile → we must learn the identity before opening the app,
      // otherwise the first screens map the user's own rows to a raw uuid
      // instead of `me`. Stay `restoring` until /me resolves.
      try {
        _adoptUser(await _repo.me());
        _set(SessionStatus.authenticated);
        _hydrateRoster();
      } on Object {
        // The interceptor force-logs-out on a real 401; a transient/offline
        // error with no cached identity can't safely open the app.
        _set(SessionStatus.unauthenticated);
      }
    }
  }

  Future<void> _refreshProfileInBackground() async {
    try {
      _adoptUser(await _repo.me());
    } on Object {
      // Offline/transient — keep the cached session; a real 401 force-logs-out.
    }
    _hydrateRoster();
  }

  void _hydrateRoster() => UserDirectory.hydrate(_ref.read(apiServiceProvider));

  SessionUser? _cachedUser() {
    final cached = AppCache.get(AppCache.authBox, _userCacheKey);
    if (cached?.data is! String) return null;
    try {
      return SessionUser.fromJson(
          jsonDecode(cached!.data as String) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  Future<LoginResult> login(String email, String password) async {
    final result = await _repo.login(email, password);
    if (result is LoginSuccess) await _adoptSession(result.session);
    return result;
  }

  Future<AuthSession> verifyTwoFactor({
    required String challengeToken,
    required String code,
  }) async {
    final session =
        await _repo.verifyTwoFactor(challengeToken: challengeToken, code: code);
    await _adoptSession(session);
    return session;
  }

  Future<TwoFactorEnrolment> startEnrolment(String enrolmentToken) =>
      _repo.startLoginEnrolment(enrolmentToken);

  /// Confirms forced enrolment. When the response carries one-time backup
  /// codes, the session is adopted but the gate is NOT promoted yet — the UI
  /// must show the codes first and then call [finalizeLogin]. Otherwise login
  /// completes immediately.
  Future<AuthSession> confirmEnrolment({
    required String enrolmentToken,
    required String code,
  }) async {
    final session = await _repo.confirmLoginEnrolment(
        enrolmentToken: enrolmentToken, code: code);
    await _adoptSession(session, promoteGate: session.backupCodes.isEmpty);
    return session;
  }

  /// Promotes the gate to authenticated after the user acknowledges their
  /// one-time backup codes (tokens were already persisted in [confirmEnrolment]).
  void finalizeLogin() {
    if (state.status == SessionStatus.authenticated) return;
    _set(SessionStatus.authenticated);
    _hydrateRoster();
  }

  Future<void> logout() async {
    final tokens = _ref.read(tokenStorageProvider);
    final refresh = tokens.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await _repo.logout(refresh);
    }
    await _clearLocalSession();
  }

  /// 401 survived refresh-and-retry, or the session was revoked.
  Future<void> forceLogout() => _clearLocalSession();

  Future<void> _adoptSession(AuthSession session, {bool promoteGate = true}) async {
    // A new session must never inherit a prior tenant's cached data or the
    // previous user's in-memory provider graph.
    await AppCache.clearAll();
    await _ref.read(tokenStorageProvider).saveTokens(
          access: session.accessToken,
          refresh: session.refreshToken,
        );
    _resetApiScopedProviders();
    _adoptUser(session.user);
    if (promoteGate) {
      _set(SessionStatus.authenticated);
      _hydrateRoster();
    }
  }

  void _adoptUser(SessionUser user) {
    if (user.id.isNotEmpty) {
      UserDirectory.currentUserId = user.id;
      UserDirectory.register(userId: user.id, fullName: user.fullName);
    }
    state = state.copyWith(user: user);
    AppCache.put(
      AppCache.authBox,
      _userCacheKey,
      jsonEncode({
        'id': user.id,
        'email': user.email,
        'full_name': user.fullName,
        // Cached too, so a warm start shows the real workspace name in the
        // header instead of blanking until the background /me lands.
        'organizations': [
          for (final o in user.organizations)
            {
              'id': o.id,
              'name': o.name,
              'subdomain': o.subdomain,
              'is_primary': o.isPrimary,
            },
        ],
      }),
    );
  }

  Future<void> _clearLocalSession() async {
    if (_tearingDown || state.status == SessionStatus.unauthenticated) return;
    _tearingDown = true;
    try {
      // Fail closed: purge cached tenant data BEFORE dropping the token, so an
      // interrupted logout leaves no data rather than orphaned data.
      await AppCache.clearAll();
      await _ref.read(tokenStorageProvider).clear();
      UserDirectory.reset();
      _resetApiScopedProviders();
      state = const SessionState(status: SessionStatus.unauthenticated);
      SessionGate.instance.set(SessionStatus.unauthenticated);
    } finally {
      _tearingDown = false;
    }
  }

  /// Invalidating the network gateway cascades a rebuild through every
  /// repository/list provider that `ref.watch`es it, discarding the previous
  /// user's retained in-memory data. The `ref.listen` above re-wires
  /// onSessionExpired onto the fresh ApiService.
  void _resetApiScopedProviders() => _ref.invalidate(apiServiceProvider);

  void _set(SessionStatus status) {
    state = state.copyWith(status: status);
    SessionGate.instance.set(status);
  }
}

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(ref),
);
