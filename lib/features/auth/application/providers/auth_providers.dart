import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_gate.dart';
import '../../../../core/config/api_config.dart';
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

  AuthRepository get _repo => _ref.read(authRepositoryProvider);

  Future<void> _init() async {
    if (!ApiConfig.apiEnabled) {
      // Mock mode has no login gate — the app boots straight into the shell.
      _set(SessionStatus.authenticated);
      return;
    }

    final api = _ref.read(apiServiceProvider);
    api.onSessionExpired = forceLogout;

    final tokens = _ref.read(tokenStorageProvider);
    await tokens.init();

    if (!tokens.hasSession) {
      _set(SessionStatus.unauthenticated);
      return;
    }

    // Optimistic restore: cached profile first so the app opens offline, then
    // a live /me/ refresh in the background.
    final cached = AppCache.get(AppCache.authBox, _userCacheKey);
    if (cached?.data is String) {
      try {
        final user = SessionUser.fromJson(
            jsonDecode(cached!.data as String) as Map<String, dynamic>);
        _adoptUser(user);
      } on Object {
        // Corrupt cache — the live fetch below still covers us.
      }
    }
    _set(SessionStatus.authenticated);

    try {
      _adoptUser(await _repo.me());
    } on Object {
      // Offline or 401 — the interceptor calls forceLogout for real auth
      // failures; transient errors keep the cached session.
    }
    UserDirectory.hydrate(api);
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

  Future<AuthSession> confirmEnrolment({
    required String enrolmentToken,
    required String code,
  }) async {
    final session = await _repo.confirmLoginEnrolment(
        enrolmentToken: enrolmentToken, code: code);
    await _adoptSession(session);
    return session;
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

  Future<void> _adoptSession(AuthSession session) async {
    await _ref.read(tokenStorageProvider).saveTokens(
          access: session.accessToken,
          refresh: session.refreshToken,
        );
    _adoptUser(session.user);
    _set(SessionStatus.authenticated);
    UserDirectory.hydrate(_ref.read(apiServiceProvider));
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
      }),
    );
  }

  Future<void> _clearLocalSession() async {
    await _ref.read(tokenStorageProvider).clear();
    await AppCache.clearAll();
    UserDirectory.reset();
    state = const SessionState(status: SessionStatus.unauthenticated);
    SessionGate.instance.set(SessionStatus.unauthenticated);
  }

  void _set(SessionStatus status) {
    state = state.copyWith(status: status);
    SessionGate.instance.set(status);
  }
}

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(ref),
);
