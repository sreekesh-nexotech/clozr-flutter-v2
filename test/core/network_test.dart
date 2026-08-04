import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/core/network/auth_interceptor.dart';
import 'package:clozrapp/core/network/paginated.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Scripts responses per (method, path). Each entry is consumed in order.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, List<ResponseBody>> script = {};
  final List<String> calls = [];

  void on(String path, int status, Object body) {
    script.putIfAbsent(path, () => []).add(
          ResponseBody.fromString(
            jsonEncode(body),
            status,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        );
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? _,
      Future<void>? __) async {
    calls.add('${options.method} ${options.path}');
    final queue = script[options.path];
    if (queue == null || queue.isEmpty) {
      return ResponseBody.fromString('{"code":404,"message":"Not found."}', 404,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });
    }
    return queue.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

/// In-memory secure storage so [TokenStorage] runs without a platform channel.
class _MemStorage extends FlutterSecureStorage {
  const _MemStorage();
  static final Map<String, String> _store = {};

  @override
  Future<String?> read(
          {required String key,
          dynamic iOptions,
          dynamic aOptions,
          dynamic lOptions,
          dynamic webOptions,
          dynamic mOptions,
          dynamic wOptions}) async =>
      _store[key];

  @override
  Future<void> write(
      {required String key,
      required String? value,
      dynamic iOptions,
      dynamic aOptions,
      dynamic lOptions,
      dynamic webOptions,
      dynamic mOptions,
      dynamic wOptions}) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete(
      {required String key,
      dynamic iOptions,
      dynamic aOptions,
      dynamic lOptions,
      dynamic webOptions,
      dynamic mOptions,
      dynamic wOptions}) async {
    _store.remove(key);
  }
}

void main() {
  group('AppError.fromDio', () {
    DioException http(int status, Object body) => DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: status,
            data: body,
          ),
        );

    test('maps the backend envelope {code, message}', () {
      final e = AppError.fromDio(http(403, {
        'code': 403,
        'message': 'You do not have permission to perform this action.',
      }));
      expect(e.type, AppErrorType.forbidden);
      expect(e.message, contains('permission'));
    });

    test('prefers concrete field errors over "Validation Error"', () {
      final e = AppError.fromDio(http(400, {
        'code': 400,
        'message': 'Validation Error',
        'errors': {
          'email': ['A user with this email already exists.']
        },
      }));
      expect(e.type, AppErrorType.validation);
      expect(e.message, contains('email'));
      expect(e.fieldErrors?['email']?.first, contains('already exists'));
    });

    test('handles raw DRF detail bodies and throttling', () {
      final e = AppError.fromDio(
          http(429, {'detail': 'Request was throttled.'}));
      expect(e.type, AppErrorType.throttled);
      expect(e.message, 'Request was throttled.');
    });

    test('HTML 500 bodies never leak into the message', () {
      final e = AppError.fromDio(http(500, '<html><body>boom</body></html>'));
      expect(e.type, AppErrorType.server);
      expect(e.message.contains('<'), isFalse);
    });

    test('connection errors map to network', () {
      final e = AppError.fromDio(DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      ));
      expect(e.type, AppErrorType.network);
    });
  });

  group('Paginated', () {
    test('parses the DRF envelope', () {
      final page = Paginated.fromJson({
        'count': 2,
        'next': 'http://x/?page=2',
        'previous': null,
        'results': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      }, (m) => m['id'] as String);
      expect(page.count, 2);
      expect(page.hasMore, isTrue);
      expect(page.results, ['a', 'b']);
    });

    test('fromAny accepts bare arrays and garbage', () {
      final bare = Paginated.fromAny([
        {'id': 'a'}
      ], (m) => m['id'] as String);
      expect(bare.results, ['a']);
      expect(Paginated.fromAny(null, (m) => m).results, isEmpty);
    });
  });

  group('AuthInterceptor', () {
    late _FakeAdapter adapter;
    late TokenStorage tokens;
    late Dio dio;
    var expired = false;

    setUp(() async {
      _MemStorage._store.clear();
      adapter = _FakeAdapter();
      tokens = TokenStorage(const _MemStorage());
      await tokens.init();
      await tokens.saveTokens(access: 'old-access', refresh: 'refresh-1');

      dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
      final bare = Dio(BaseOptions(baseUrl: 'https://api.test'));
      dio.httpClientAdapter = adapter;
      bare.httpClientAdapter = adapter;
      expired = false;
      dio.interceptors.add(AuthInterceptor(
        tokens: tokens,
        retryClient: bare,
        refreshUrl: '/auth/login/refresh/',
        onSessionExpired: () => expired = true,
      ));
    });

    test('attaches the bearer header', () async {
      adapter.on('/crm/leads/', 200, {'results': []});
      RequestOptions? seen;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seen = o;
        h.next(o);
      }));
      await dio.get<dynamic>('/crm/leads/');
      expect(seen?.headers['Authorization'], 'Bearer old-access');
    });

    test('401 → refresh → retry once with the new token', () async {
      adapter.on('/crm/leads/', 401, {'code': 401, 'message': 'expired'});
      adapter.on('/auth/login/refresh/', 200, {'access': 'new-access'});
      adapter.on('/crm/leads/', 200, {'count': 0, 'results': []});

      final res = await dio.get<dynamic>('/crm/leads/');
      expect(res.statusCode, 200);
      expect(tokens.accessToken, 'new-access');
      expect(expired, isFalse);
      expect(adapter.calls.where((c) => c.contains('refresh')).length, 1);
    });

    test('failed refresh clears tokens and fires session expiry', () async {
      adapter.on('/crm/leads/', 401, {'code': 401, 'message': 'expired'});
      adapter.on('/auth/login/refresh/', 401,
          {'code': 401, 'message': 'Token is blacklisted'});

      await expectLater(dio.get<dynamic>('/crm/leads/'), throwsA(isA<DioException>()));
      expect(expired, isTrue);
      expect(tokens.hasSession, isFalse);
    });

    test('session_revoked logs out immediately without refreshing', () async {
      adapter.on('/crm/leads/', 401,
          {'detail': 'Session has been revoked.', 'code': 'session_revoked'});

      await expectLater(dio.get<dynamic>('/crm/leads/'), throwsA(isA<DioException>()));
      expect(expired, isTrue);
      expect(adapter.calls.any((c) => c.contains('refresh')), isFalse);
    });

    test('anonymous auth paths never get a bearer header', () async {
      adapter.on('/auth/login/', 200, {'access_token': 'x'});
      RequestOptions? seen;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seen = o;
        h.next(o);
      }));
      await dio.post<dynamic>('/auth/login/', data: {'email': 'a'});
      expect(seen?.headers.containsKey('Authorization'), isFalse);
    });
  });
}
