import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../data_sources/remote/auth_remote_ds.dart';

/// API-backed [AuthRepository]. Thin — auth has no mock/cache variant; in
/// mock mode the session layer never engages.
class AuthApiRepository implements AuthRepository {
  const AuthApiRepository(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Future<LoginResult> login(String email, String password) =>
      _remote.login(email, password);

  @override
  Future<AuthSession> verifyTwoFactor({
    required String challengeToken,
    required String code,
  }) =>
      _remote.verifyTwoFactor(challengeToken: challengeToken, code: code);

  @override
  Future<TwoFactorEnrolment> startLoginEnrolment(String enrolmentToken) =>
      _remote.startLoginEnrolment(enrolmentToken);

  @override
  Future<AuthSession> confirmLoginEnrolment({
    required String enrolmentToken,
    required String code,
  }) =>
      _remote.confirmLoginEnrolment(enrolmentToken: enrolmentToken, code: code);

  @override
  Future<void> logout(String refreshToken) async {
    try {
      await _remote.logout(refreshToken);
    } on Object {
      // Server-side blacklist is best-effort; local logout always proceeds.
    }
  }

  @override
  Future<SessionUser> me() => _remote.me();
}
