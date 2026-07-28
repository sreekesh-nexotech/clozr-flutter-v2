/// Encrypted storage for session tokens and PII (Keychain / Keystore).
///
/// The concrete implementation lands with the integration PR — it needs
/// `flutter_secure_storage`, which docs-flutter/Technical_stack.md lists for
/// session tokens but which is not a dependency yet.
///
/// NOTE — conflicting guidance in the docs, resolved in favour of security:
/// Flutter Coding Standards §6.2 says "store access/refresh tokens in Hive
/// only", but §9 says "never store sensitive data in Hive", and
/// Technical_stack.md nominates `flutter_secure_storage` for session tokens.
/// This contract follows §9 + Technical_stack: tokens go here, never in a Hive
/// box. Raise it with the team if §6.2 was meant literally.
// TODO(clozr): add FlutterSecureStorage implementation 2026-07-28
abstract interface class SecureStore {
  /// Reads a value, or `null` when the key is absent.
  Future<String?> readAsync(String key);

  /// Writes [value] under [key], replacing any existing entry.
  Future<void> writeAsync(String key, String value);

  /// Removes a single entry.
  Future<void> deleteAsync(String key);

  /// Wipes every entry. Call on logout.
  Future<void> clearAsync();
}

/// Keys stored in [SecureStore].
///
/// Anything listed here is sensitive by definition: never log it, never write
/// it to Hive, and never include it in a crash report (QA.md item 13).
class SecureStoreKeys {
  const SecureStoreKeys._();

  /// Session cookie / access token issued at login.
  static const String sessionToken = 'session_token';

  /// Refresh token used by the 401 retry flow.
  static const String refreshToken = 'refresh_token';

  /// Absolute expiry of [sessionToken] as an ISO-8601 string.
  static const String sessionExpiresAt = 'session_expires_at';

  /// Device identifier registered for push delivery.
  static const String deviceToken = 'device_token';

  /// Every key, for the logout wipe.
  static const List<String> all = [
    sessionToken,
    refreshToken,
    sessionExpiresAt,
    deviceToken,
  ];
}
