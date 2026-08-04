import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

/// Attaches the JWT to outgoing requests and transparently recovers from
/// expired access tokens: on a 401 it refreshes once (single-flight), retries
/// the original request once, and if that still fails surfaces the 401 and
/// fires [onSessionExpired] so the auth layer can log the user out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStorage tokens,
    required Dio retryClient,
    required String refreshUrl,
    this.onSessionExpired,
  })  : _tokens = tokens,
        _retryClient = retryClient,
        _refreshUrl = refreshUrl;

  final TokenStorage _tokens;

  /// A bare Dio (no interceptors) used for the refresh call and the retry, so
  /// a failing refresh can never recurse back into this interceptor.
  final Dio _retryClient;

  final String _refreshUrl;

  void Function()? onSessionExpired;

  /// In-flight refresh, shared so concurrent 401s trigger a single call.
  Future<bool>? _refreshing;

  /// Endpoints that authenticate via tokens in the *body* (AllowAny) — a
  /// bearer header must never be attached to these.
  static const List<String> _anonymousPaths = [
    '/auth/login/',
    '/auth/login/2fa/',
    '/auth/login/2fa/enrol/start/',
    '/auth/login/2fa/enrol/confirm/',
    '/auth/login/refresh/',
    '/auth/password-reset/',
    '/auth/password-reset/confirm/',
    '/auth/activate-account/confirm/',
  ];

  static bool _isAnonymous(String path) =>
      _anonymousPaths.any((p) => path.endsWith(p));

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final access = _tokens.accessToken;
    if (access != null && !_isAnonymous(options.path)) {
      options.headers['Authorization'] = 'Bearer $access';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final options = err.requestOptions;

    // A revoked session must NOT refresh — its refresh token would still mint
    // access tokens. Log out immediately.
    if (response?.statusCode == 401 && _isSessionRevoked(response?.data)) {
      await _tokens.clear();
      onSessionExpired?.call();
      handler.next(err);
      return;
    }

    final shouldAttemptRefresh = response?.statusCode == 401 &&
        !_isAnonymous(options.path) &&
        options.extra['retried'] != true &&
        _tokens.hasSession;

    if (!shouldAttemptRefresh) {
      handler.next(err);
      return;
    }

    final refreshed = await (_refreshing ??= _refresh());
    if (!refreshed) {
      onSessionExpired?.call();
      handler.next(err);
      return;
    }

    try {
      options.extra['retried'] = true;
      options.headers['Authorization'] = 'Bearer ${_tokens.accessToken}';
      final retry = await _retryClient.fetch<dynamic>(options);
      handler.resolve(retry);
    } on DioException catch (retryErr) {
      if (retryErr.response?.statusCode == 401) onSessionExpired?.call();
      handler.next(retryErr);
    }
  }

  static bool _isSessionRevoked(Object? body) =>
      body is Map && body['code'] == 'session_revoked';

  Future<bool> _refresh() async {
    try {
      final refresh = _tokens.refreshToken;
      if (refresh == null || refresh.isEmpty) return false;
      final res = await _retryClient.post<Map<String, dynamic>>(
        _refreshUrl,
        data: {'refresh': refresh},
      );
      // SimpleJWT returns `access`; the login endpoint's dialect is
      // `access_token` — accept either for safety.
      final data = res.data;
      final access = (data?['access'] ?? data?['access_token']) as String?;
      if (access == null || access.isEmpty) return false;
      await _tokens.updateAccess(access);
      return true;
    } on DioException {
      await _tokens.clear();
      return false;
    } finally {
      _refreshing = null;
    }
  }
}
