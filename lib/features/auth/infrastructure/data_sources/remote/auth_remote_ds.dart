import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/app_error.dart';
import '../../../domain/entities/auth_session.dart';
import '../../../domain/entities/module_access.dart';

/// Raw auth endpoints. HTTP + JSON→entity mapping only — token persistence
/// and session state live above this layer.
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._api);

  final ApiService _api;

  Future<LoginResult> login(String email, String password) async {
    final body = await _api.post(
      ApiEndpoints.login,
      body: {'email': email, 'password': password},
    );
    return _parseLoginOutcome(body);
  }

  Future<AuthSession> verifyTwoFactor({
    required String challengeToken,
    required String code,
  }) async {
    final body = await _api.post(
      ApiEndpoints.login2fa,
      body: {'challenge_token': challengeToken, 'code': code},
    );
    return _session(body);
  }

  Future<TwoFactorEnrolment> startLoginEnrolment(String enrolmentToken) async {
    final body = await _api.post(
      ApiEndpoints.login2faEnrolStart,
      body: {'enrolment_token': enrolmentToken},
    );
    return TwoFactorEnrolment.fromJson(_asMap(body));
  }

  Future<AuthSession> confirmLoginEnrolment({
    required String enrolmentToken,
    required String code,
  }) async {
    final body = await _api.post(
      ApiEndpoints.login2faEnrolConfirm,
      body: {'enrolment_token': enrolmentToken, 'code': code},
    );
    return _session(body);
  }

  Future<void> logout(String refreshToken) =>
      _api.post(ApiEndpoints.logout, body: {'refresh': refreshToken});

  Future<SessionUser> me() async =>
      SessionUser.fromJson(_asMap(await _api.get(ApiEndpoints.me)));

  Future<ModuleAccess> modules() async =>
      ModuleAccess.fromJson(_asMap(await _api.get(ApiEndpoints.myModules)));

  // ── mapping ──

  /// Three 200 shapes; only `access_token` means login completed (this is
  /// also how the backend itself branches).
  static LoginResult _parseLoginOutcome(Object? body) {
    final map = _asMap(body);
    if ((map['access_token'] as String?)?.isNotEmpty ?? false) {
      return LoginSuccess(_session(map));
    }
    if (map['two_factor_required'] == true) {
      return LoginTwoFactorRequired(
        challengeToken: map['challenge_token'] as String? ?? '',
        methods: (map['methods'] as List? ?? const ['totp'])
            .whereType<String>()
            .toList(),
        expiresIn: (map['expires_in'] as num?)?.toInt() ?? 300,
      );
    }
    if (map['two_factor_setup_required'] == true) {
      return LoginEnrolmentRequired(
        enrolmentToken: map['enrolment_token'] as String? ?? '',
        message: map['message'] as String? ?? '',
        expiresIn: (map['expires_in'] as num?)?.toInt() ?? 900,
      );
    }
    throw const AppError(
      type: AppErrorType.unknown,
      message: 'Unexpected response from the server.',
    );
  }

  static AuthSession _session(Object? body) {
    final map = _asMap(body);
    final access = map['access_token'] as String? ?? '';
    final refresh = map['refresh_token'] as String? ?? '';
    if (access.isEmpty || refresh.isEmpty) {
      throw const AppError(
        type: AppErrorType.unknown,
        message: 'Login response was missing tokens.',
      );
    }
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      user: SessionUser.fromJson(_asMap(map['user'])),
      backupCodes:
          (map['backup_codes'] as List? ?? const []).whereType<String>().toList(),
      backupCodesRemaining: (map['backup_codes_remaining'] as num?)?.toInt(),
    );
  }

  static Map<String, dynamic> _asMap(Object? body) =>
      body is Map<String, dynamic> ? body : <String, dynamic>{};
}
