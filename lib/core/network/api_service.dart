import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'app_error.dart';
import 'auth_interceptor.dart';

/// The single network gateway (rule 6.1: one ApiService for all calls).
///
/// Feature repositories talk to this class only — never to Dio directly — so
/// auth headers, token refresh, logging and error normalization live in one
/// place. Every method returns decoded JSON (`Map`/`List`) and throws
/// [AppError] on failure.
class ApiService {
  ApiService({required TokenStorage tokens, Dio? dio, Dio? refreshDio})
      : _tokens = tokens {
    final base = BaseOptions(
      baseUrl: '${ApiConfig.baseUrl}${ApiConfig.apiPrefix}',
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      sendTimeout: ApiConfig.sendTimeout,
      headers: {'Accept': 'application/json'},
    );

    _dio = dio ?? Dio(base);
    final bare = refreshDio ?? Dio(base);

    _authInterceptor = AuthInterceptor(
      tokens: _tokens,
      retryClient: bare,
      refreshUrl: '/auth/login/refresh/',
    );
    _dio.interceptors.add(_authInterceptor);

    if (kDebugMode) {
      _dio.interceptors.add(PrettyDioLogger(
        requestBody: true,
        responseBody: false,
        compact: true,
      ));
    }
  }

  final TokenStorage _tokens;
  late final Dio _dio;
  late final AuthInterceptor _authInterceptor;

  TokenStorage get tokens => _tokens;

  /// Called when a 401 survives the refresh-and-retry cycle. The auth
  /// controller registers itself here to force a logout.
  set onSessionExpired(void Function()? handler) {
    _authInterceptor.onSessionExpired = handler;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _run(() => _dio.get<dynamic>(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _run(() => _dio.post<dynamic>(path, data: body, queryParameters: query));

  Future<dynamic> put(String path, {Object? body}) =>
      _run(() => _dio.put<dynamic>(path, data: body));

  Future<dynamic> patch(String path, {Object? body}) =>
      _run(() => _dio.patch<dynamic>(path, data: body));

  Future<dynamic> delete(String path, {Object? body}) =>
      _run(() => _dio.delete<dynamic>(path, data: body));

  /// Multipart upload (attachments, call recordings).
  Future<dynamic> postForm(String path, FormData form) =>
      _run(() => _dio.post<dynamic>(path, data: form));

  Future<dynamic> _run(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return res.data;
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}
