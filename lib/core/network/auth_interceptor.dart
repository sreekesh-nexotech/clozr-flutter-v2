import 'dart:convert';

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

  /// Why the server ended the session, when it said so — one of
  /// [terminalSessionCodes]. Set just before [onSessionExpired] fires, null
  /// for an ordinary expiry, so the login screen can explain the sign-out.
  String? lastSignOutReason;

  /// The 401 `code`s the webapp treats as final: no refresh, sign out, and the
  /// login screen says why (webapp `terminalSessionCode.ts`).
  static const terminalSessionCodes = {
    'session_force_signout',
    'session_revoked',
    'session_expired',
    'user_inactive',
    'session_outside_work_hours',
  };

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

  /// Off for the rest of the session once a token that was just issued
  /// already reads as expired by this device's clock (a skewed clock would
  /// otherwise refresh before every request).
  bool _preflightDisabled = false;

  /// How close to its `exp` a token counts as expired: refreshing a little
  /// early beats a request that expires in flight.
  static const preflightMargin = Duration(seconds: 30);

  /// The `exp` of a JWT, or null for anything that is not a readable JWT.
  static DateTime? tokenExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000,
          isUtc: true);
    } on Object {
      return null;
    }
  }

  /// Whether [token] is expired, or within [preflightMargin] of it.
  static bool expiresSoon(String token, {DateTime? now}) {
    final exp = tokenExpiry(token);
    if (exp == null) return false; // unknown: let the 401 path decide
    return !exp.isAfter((now ?? DateTime.now()).toUtc().add(preflightMargin));
  }

  /// Webapp parity (C22): after an idle longer than the access token's life,
  /// the next screen used to send every request, take a 401 each, then wait
  /// for the refresh and replay. The token's `exp` is read first instead and
  /// one shared refresh happens before sending. Any doubt (not a JWT, failed
  /// refresh, skewed clock) falls back to the existing 401 › refresh › replay.
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isAnonymous(options.path)) {
      var access = _tokens.accessToken;
      if (!_preflightDisabled &&
          access != null &&
          _tokens.hasSession &&
          expiresSoon(access)) {
        final refreshed = await (_refreshing ??= _refresh());
        if (refreshed) {
          access = _tokens.accessToken;
          if (access != null && expiresSoon(access)) {
            _preflightDisabled = true;
          }
        }
      }
      if (access != null) {
        options.headers['Authorization'] = 'Bearer $access';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final options = err.requestOptions;

    // A revoked session must NOT refresh — its refresh token would still mint
    // access tokens. Log out immediately.
    final terminal =
        response?.statusCode == 401 ? _terminalCode(response?.data) : null;
    if (terminal != null && !_isAnonymous(options.path)) {
      await _tokens.clear();
      lastSignOutReason = terminal;
      onSessionExpired?.call();
      handler.next(err);
      return;
    }
    lastSignOutReason = null;

    final shouldAttemptRefresh = response?.statusCode == 401 &&
        !_isAnonymous(options.path) &&
        options.extra['retried'] != true &&
        _tokens.hasSession;

    if (!shouldAttemptRefresh) {
      handler.next(err);
      return;
    }

    // Sent with a token that has since been replaced (another request
    // refreshed meanwhile): replay with the current one, no second refresh.
    final sentWith = '${options.headers['Authorization'] ?? ''}';
    final current = _tokens.accessToken;
    final replaced =
        current != null && sentWith.isNotEmpty && sentWith != 'Bearer $current';
    final refreshed = replaced || await (_refreshing ??= _refresh());
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

  /// The terminal reason in a 401 body, or null. A deactivated account is
  /// answered with a numeric code and the message "User is inactive"; it is
  /// read as `user_inactive` because refreshing cannot revive it either.
  static String? _terminalCode(Object? body) {
    if (body is! Map) return null;
    final code = body['code'];
    if (code is String && terminalSessionCodes.contains(code)) return code;
    final message =
        (body['message'] ?? body['detail'])?.toString().trim().toLowerCase();
    if (message == 'user is inactive') return 'user_inactive';
    return null;
  }

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
      // A rotated refresh token is kept (the old one may be blacklisted).
      final rotated = (data?['refresh'] ?? data?['refresh_token']) as String?;
      if (rotated != null && rotated.isNotEmpty) {
        await _tokens.saveTokens(access: access, refresh: rotated);
      } else {
        await _tokens.updateAccess(access);
      }
      return true;
    } on DioException {
      await _tokens.clear();
      return false;
    } finally {
      _refreshing = null;
    }
  }
}
