import 'package:equatable/equatable.dart';

/// Organization membership summary from the login/me payloads.
class OrgSummary extends Equatable {
  const OrgSummary({
    required this.id,
    required this.name,
    this.subdomain = '',
    this.isPrimary = false,
  });

  final String id;
  final String name;
  final String subdomain;
  final bool isPrimary;

  factory OrgSummary.fromJson(Map<String, dynamic> json) => OrgSummary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        subdomain: json['subdomain'] as String? ?? '',
        isPrimary: json['is_primary'] == true,
      );

  @override
  List<Object?> get props => [id];
}

/// The signed-in user.
class SessionUser extends Equatable {
  const SessionUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.organizations = const [],
  });

  final String id;
  final String email;
  final String fullName;
  final List<OrgSummary> organizations;

  OrgSummary? get primaryOrg => organizations.isEmpty
      ? null
      : organizations.firstWhere((o) => o.isPrimary, orElse: () => organizations.first);

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        id: json['id'] as String? ?? json['user_id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        organizations: (json['organizations'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OrgSummary.fromJson)
            .toList(),
      );

  @override
  List<Object?> get props => [id, email];
}

/// A completed login: token pair + user.
class AuthSession extends Equatable {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.backupCodes = const [],
    this.backupCodesRemaining,
  });

  final String accessToken;
  final String refreshToken;
  final SessionUser user;

  /// Present only right after a forced 2FA enrolment — shown once.
  final List<String> backupCodes;

  /// Present when a backup code (not TOTP) cleared the second factor.
  final int? backupCodesRemaining;

  @override
  List<Object?> get props => [accessToken, refreshToken, user];
}

/// TOTP enrolment material (QR payload + manual secret).
class TwoFactorEnrolment extends Equatable {
  const TwoFactorEnrolment({
    required this.secret,
    required this.provisioningUri,
    this.issuer = '',
  });

  final String secret;
  final String provisioningUri;
  final String issuer;

  factory TwoFactorEnrolment.fromJson(Map<String, dynamic> json) =>
      TwoFactorEnrolment(
        secret: json['secret'] as String? ?? '',
        provisioningUri: json['provisioning_uri'] as String? ?? '',
        issuer: json['issuer'] as String? ?? '',
      );

  @override
  List<Object?> get props => [secret];
}

/// `POST /auth/login/` is polymorphic across three HTTP-200 shapes — only the
/// presence of `access_token` means login actually completed.
sealed class LoginResult {
  const LoginResult();
}

class LoginSuccess extends LoginResult {
  const LoginSuccess(this.session);
  final AuthSession session;
}

/// 2FA device exists — collect a TOTP/backup code (§1b of login.md).
class LoginTwoFactorRequired extends LoginResult {
  const LoginTwoFactorRequired({
    required this.challengeToken,
    this.methods = const ['totp'],
    this.expiresIn = 300,
  });

  final String challengeToken;
  final List<String> methods;
  final int expiresIn;
}

/// Org mandates 2FA and this account has no device yet (§1c).
class LoginEnrolmentRequired extends LoginResult {
  const LoginEnrolmentRequired({
    required this.enrolmentToken,
    this.message = '',
    this.expiresIn = 900,
  });

  final String enrolmentToken;
  final String message;
  final int expiresIn;
}
