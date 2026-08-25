import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The work email to prefill on the sign-in screen, when the user asked for it.
///
/// Only the email. A password is never stored — the session already survives a
/// restart through [TokenStorage], so "remember me" here is about not retyping
/// an address, not about holding a credential.
///
/// Kept in the same secure store as the tokens rather than in plain
/// preferences: a work email identifies the person and their employer, which is
/// not something to leave in clear text on a shared or lost device.
class RememberedEmail {
  RememberedEmail([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'auth_remembered_email';

  final FlutterSecureStorage _storage;

  /// The remembered address, or null when the box was left unticked (or the
  /// user has since unticked it).
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Remembers [email], or forgets it when [remember] is false — so unticking
  /// the box on the next sign-in clears what an earlier one stored.
  Future<void> save(String email, {required bool remember}) async {
    if (!remember) return clear();
    final trimmed = email.trim();
    if (trimmed.isEmpty) return clear();
    await _storage.write(key: _key, value: trimmed);
  }

  Future<void> clear() => _storage.delete(key: _key);
}
