import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
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

  // Callers swallow errors on purpose in two places: best-effort reads (a
  // schema, an option catalog, the audit log) so a screen never blanks, and the
  // notes composer so typing is not lost. The gateway announces them anyway,
  // which is what lets the shell say what happened.
  group('ApiService announces failures the caller may swallow', () {
    late _FakeAdapter adapter;
    late ApiService api;

    setUp(() async {
      _MemStorage._store.clear();
      final tokens = TokenStorage(const _MemStorage());
      await tokens.init();
      await tokens.saveTokens(access: 'a', refresh: 'r');

      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
      final bare = Dio(BaseOptions(baseUrl: 'https://api.test'));
      adapter = _FakeAdapter();
      dio.httpClientAdapter = adapter;
      bare.httpClientAdapter = adapter;
      api = ApiService(tokens: tokens, dio: dio, refreshDio: bare);
    });

    test('a 403 read publishes, even when the caller swallows it', () async {
      adapter.on('/crm/lead-statuses/', 403,
          {'code': 403, 'message': 'You do not have permission to view statuses.'});

      // Exactly what the catalog data sources do.
      try {
        await api.get('/crm/lead-statuses/');
      } on Object {
        // swallowed, as designed
      }

      expect(api.failures.value?.type, AppErrorType.forbidden);
      expect(api.failures.value?.message,
          'You do not have permission to view statuses.');
    });

    test('a rejected write publishes its field error', () async {
      // The real shape: the notes POST refused for an unsupported related_to.
      adapter.on('/crm/notes/', 400, {
        'code': 400,
        'message': 'Validation Error',
        'errors': {
          'related_to': ['Invalid model name. Must be one of: lead, …, quotation']
        },
      });

      // The notes composer swallows this to keep its optimistic entry.
      try {
        await api.post('/crm/notes/', body: {'related_to': 'payment'});
      } on Object {
        // swallowed, as designed
      }

      // The generic "Validation Error" would tell the user nothing; the field
      // error is the sentence worth showing.
      expect(api.failures.value?.message,
          'related_to: Invalid model name. Must be one of: lead, …, quotation');
    });

    test('a failed read that is not a refusal stays quiet', () async {
      // `payments/schema/` 404s on every load of two screens. Announcing that
      // each time would bury the messages that matter.
      adapter.on('/quotations/payments/schema/', 404,
          {'code': 404, 'message': 'Not found.'});

      await expectLater(
          api.get('/quotations/payments/schema/'), throwsA(isA<AppError>()));
      expect(api.failures.value, isNull);
    });

    test('a 401 stays quiet — the interceptor logs out instead', () async {
      adapter.on('/crm/leads/', 401, {'code': 401, 'message': 'expired'});

      await expectLater(api.post('/crm/leads/'), throwsA(isA<AppError>()));
      expect(api.failures.value, isNull);
    });

    test('a successful call publishes nothing', () async {
      adapter.on('/crm/leads/', 200, {'count': 0, 'results': []});

      await api.get('/crm/leads/');
      expect(api.failures.value, isNull);
    });
  });
}
