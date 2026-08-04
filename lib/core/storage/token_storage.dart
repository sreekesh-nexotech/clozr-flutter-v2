import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT pair in the platform keychain/keystore.
///
/// Tokens never touch Hive (security rule: no sensitive data in Hive) and are
/// only read here and in the auth interceptor. An in-memory copy backs
/// synchronous reads on the hot request path.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';

  final FlutterSecureStorage _storage;

  String? _access;
  String? _refresh;
  bool _loaded = false;

  /// Loads tokens from disk once at startup. Safe to call repeatedly.
  Future<void> init() async {
    if (_loaded) return;
    _access = await _storage.read(key: _accessKey);
    _refresh = await _storage.read(key: _refreshKey);
    _loaded = true;
  }

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get hasSession => _refresh != null && _refresh!.isNotEmpty;

  Future<void> saveTokens({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
    _loaded = true;
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> updateAccess(String access) async {
    _access = access;
    await _storage.write(key: _accessKey, value: access);
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
