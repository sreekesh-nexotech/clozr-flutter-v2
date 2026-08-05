import '../entities/auth_session.dart';
import '../entities/module_access.dart';

/// Auth contract. The session controller depends only on this; the remote
/// implementation lives in infrastructure.
abstract class AuthRepository {
  /// Credential login. May complete, or demand a second factor — see
  /// [LoginResult].
  Future<LoginResult> login(String email, String password);

  /// §2: verify a TOTP/backup code for the 1b branch. Mints the real JWTs.
  Future<AuthSession> verifyTwoFactor({
    required String challengeToken,
    required String code,
  });

  /// §3a: start forced enrolment (org requires 2FA, no device yet).
  Future<TwoFactorEnrolment> startLoginEnrolment(String enrolmentToken);

  /// §3b: confirm the first TOTP code — also finishes login.
  Future<AuthSession> confirmLoginEnrolment({
    required String enrolmentToken,
    required String code,
  });

  /// Blacklists the refresh token server-side. Never throws on failure —
  /// local logout must always succeed.
  Future<void> logout(String refreshToken);

  /// `GET /auth/me/` — the signed-in user's profile.
  Future<SessionUser> me();

  /// `GET /auth/me/modules/` — the module-access map that gates the nav.
  Future<ModuleAccess> modules();
}
