import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'app_error.dart';
import 'approval_hold.dart';
import 'auth_interceptor.dart';
import 'mandatory_course_block.dart';

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
      // requestBody stays OFF: login/2FA/logout bodies carry passwords, OTP /
      // backup codes, and the refresh token — never log them, even in debug.
      //
      // TEMPORARY: responseBody is ON to inspect the payload shape (which
      // columns the org's field config actually sends). It dumps every response
      // in full — including `/auth/login/` and `/auth/login/refresh/`, whose
      // bodies ARE the JWT pair. Set it back to false once you have what you
      // need, and don't share these logs meanwhile.
      _dio.interceptors.add(PrettyDioLogger(
        requestBody: false,
        responseBody: true,
        requestHeader: false,
        compact: true,
      ));
    }

    // Must be the last step of the Dio setup — `addSentry` wraps whatever
    // adapter/transformer/interceptors are configured by this point.
    //
    // Guarded on the live SDK rather than on the DSN so unit tests, which build
    // an ApiService around a mock adapter without ever calling
    // `SentryFlutter.init`, keep an untouched Dio. Only 5xx responses become
    // issues (sentry_dio's default); 4xx are the backend answering correctly
    // and the UI already explains them. Bodies and headers stay out of the
    // event because `sendDefaultPii` is off.
    if (Sentry.isEnabled) _dio.addSentry();
  }

  final TokenStorage _tokens;
  late final Dio _dio;
  late final AuthInterceptor _authInterceptor;

  final ValueNotifier<int> _writes = ValueNotifier<int>(0);

  /// Ticks once after every successful write the app makes — POST, PUT, PATCH,
  /// DELETE, from anywhere.
  ///
  /// Views that show "what has happened to this record" (the activity log above
  /// all) reflect *every* action rather than one list, so hooking each call
  /// site cannot stay correct as actions are added. Signalling here, at the one
  /// point every request already passes through, means a new action announces
  /// itself for free.
  ValueListenable<int> get writes => _writes;

  final ValueNotifier<ApprovalHold?> _holds =
      ValueNotifier<ApprovalHold?>(null);

  /// Every write the server accepted but held for approval (`202
  /// APPROVAL_REQUIRED`, a bulk write's `pending_ids`, a due-date move's
  /// pending change) — a fresh event per answer, so each one notifies.
  ///
  /// Published here, at the one point every request passes through, for the
  /// same reason as [writes]: the shell turns it into the "Sent for approval"
  /// toast and the approvals refresh, so no save path can forget to.
  ValueListenable<ApprovalHold?> get holds => _holds;

  final ValueNotifier<AppError?> _failures = ValueNotifier<AppError?>(null);

  /// The most recent failure the user ought to hear about, with the backend's
  /// own wording.
  ///
  /// Published here rather than left to call sites because many of them cannot
  /// report it. Best-effort fetches swallow their errors by design
  /// (`catch (Object) → empty`) so a screen never blanks, and the notes thread
  /// deliberately keeps its optimistic entry when a POST fails. Those choices
  /// are right for reads and for not losing the user's typing — but they also
  /// meant a rejected write disappeared entirely.
  ///
  /// Two things qualify, and the split is the point:
  ///
  /// * **Any failed write** (POST/PUT/PATCH/DELETE). The user asked for
  ///   something and it did not happen; that is never not worth saying.
  /// * **Any 403**, on any method — a permission refusal explains a screen
  ///   that renders with pieces missing.
  ///
  /// A failed **read** is otherwise left quiet on purpose: `payments/schema/`
  /// 404s on every load of two screens, and announcing that each time would
  /// train the user to ignore the toast that matters.
  ValueListenable<AppError?> get failures => _failures;

  final ValueNotifier<List<IncompleteCourse>?> _courseBlocks =
      ValueNotifier(null);

  /// Every mandatory-course 403 (`mandatory_course_incomplete`), carrying the
  /// courses the server says are unfinished — a fresh list per refusal, so
  /// each one notifies. The shell turns it into the app-wide blocking screen
  /// (webapp: the Axios interceptor → `onMandatoryCourseBlock`).
  ValueListenable<List<IncompleteCourse>?> get courseBlocks => _courseBlocks;

  /// Raises the course block for a mandatory-course 403. True when it was one
  /// — the blocking screen explains it, so it is kept off [failures].
  bool _raiseCourseBlock(DioException e) {
    if (e.response?.statusCode != 403) return false;
    final body = e.response?.data;
    if (!isMandatoryCourseBlock(body)) return false;
    _courseBlocks.value = parseIncompleteCourses(body);
    return true;
  }

  TokenStorage get tokens => _tokens;

  /// Called when a 401 survives the refresh-and-retry cycle. The auth
  /// controller registers itself here to force a logout.
  set onSessionExpired(void Function()? handler) {
    _authInterceptor.onSessionExpired = handler;
  }

  /// The server's reason for the last forced sign-out (a terminal 401 code),
  /// or null when the session simply expired.
  String? get signOutReason => _authInterceptor.lastSignOutReason;

  /// [quiet] keeps a refusal off [failures]: for optional, best-effort reads
  /// (a filter's option list, a status probe) whose caller already falls back
  /// on its own. Without it, a role that can read a list but not its side
  /// catalogs got "You do not have permission…" over a screen that loaded
  /// fine. The error is still thrown to the caller.
  Future<dynamic> get(String path,
          {Map<String, dynamic>? query, bool quiet = false}) =>
      _run(() => _dio.get<dynamic>(path, queryParameters: query), quiet: quiet);

  /// Every page of a paginated list, in order, as one `{count, next: null,
  /// previous: null, results}` body — the shape a single [get] returns, so a
  /// caller can switch over without changing how it reads the answer.
  ///
  /// Webapp parity (C24): user / team option lists asked for one page
  /// (100–200 rows) and silently dropped the rest in a larger org. Page 1
  /// gives the total; the remaining pages are fetched in parallel. A one-page
  /// org still makes exactly one request. A bare-array answer is returned as
  /// is. [maxPages] caps a runaway count.
  Future<dynamic> getAllPages(String path,
      {Map<String, dynamic>? query,
      bool quiet = false,
      int maxPages = 50}) async {
    final first = await get(path, query: query, quiet: quiet);
    if (first is! Map || first['results'] is! List || first['next'] == null) {
      return first;
    }
    final rows = <dynamic>[...first['results'] as List];
    final count = first['count'] is num ? (first['count'] as num).toInt() : 0;
    final perPage = rows.length;
    if (perPage == 0) return first;
    var pages = count > 0 ? (count / perPage).ceil() : 2;
    if (pages > maxPages) pages = maxPages;
    final rest = await Future.wait([
      for (var p = 2; p <= pages; p++)
        get(path, query: {...?query, 'page': p}, quiet: quiet),
    ]);
    for (final body in rest) {
      if (body is Map && body['results'] is List) {
        rows.addAll(body['results'] as List);
      }
    }
    // The count was only an estimate (rows added mid-load): keep paging.
    var last = rest.isEmpty ? first : rest.last;
    var page = pages;
    while (last is Map && last['next'] != null && page < maxPages) {
      page++;
      last = await get(path, query: {...?query, 'page': page}, quiet: quiet);
      if (last is Map && last['results'] is List) {
        rows.addAll(last['results'] as List);
      }
    }
    return <String, dynamic>{
      'count': rows.length,
      'next': null,
      'previous': null,
      'results': rows,
    };
  }

  /// [background] is for bookkeeping writes the user did not make as an edit
  /// (product-tour progress): no refresh tick for the lists, no toast on
  /// failure — the caller retries on its own.
  Future<dynamic> post(String path,
          {Object? body,
          Map<String, dynamic>? query,
          bool background = false}) =>
      _run(() => _dio.post<dynamic>(path, data: body, queryParameters: query),
          quiet: background, countsAsWrite: !background);

  Future<dynamic> put(String path, {Object? body}) =>
      _run(() => _dio.put<dynamic>(path, data: body));

  /// [headers] carries per-request headers — `If-Match` for optimistic locking
  /// on record edits.
  Future<dynamic> patch(String path,
          {Object? body,
          Map<String, dynamic>? headers,
          bool background = false}) =>
      _run(
          () => _dio.patch<dynamic>(path,
              data: body,
              options: headers == null ? null : Options(headers: headers)),
          quiet: background,
          countsAsWrite: !background);

  /// [patch] that also hands back the HTTP status — a due-date move answers
  /// 202 when it went to a manager for approval instead of being applied.
  Future<(int status, dynamic data)> patchWithStatus(String path,
      {Object? body}) async {
    int status = 0;
    final data = await _run(() async {
      final res = await _dio.patch<dynamic>(path, data: body);
      status = res.statusCode ?? 0;
      return res;
    });
    return (status, data);
  }

  /// [post] that also hands back the HTTP status — a lead conversion answers
  /// 202 when it went for approval instead of being applied.
  Future<(int status, dynamic data)> postWithStatus(String path,
      {Object? body}) async {
    int status = 0;
    final data = await _run(() async {
      final res = await _dio.post<dynamic>(path, data: body);
      status = res.statusCode ?? 0;
      return res;
    });
    return (status, data);
  }

  /// [quiet]: a best-effort delete (cleaning up after another write) whose
  /// refusal must not reach the shell's toast.
  Future<dynamic> delete(String path, {Object? body, bool quiet = false}) =>
      _run(() => _dio.delete<dynamic>(path, data: body), quiet: quiet);

  /// Multipart upload (attachments, call recordings).
  Future<dynamic> postForm(String path, FormData form) =>
      _run(() => _dio.post<dynamic>(path, data: form));

  /// Authenticated binary download (the WhatsApp media proxy and similar) —
  /// separate from [_run] because a caller here needs the response headers
  /// (`Content-Type`, to pick a file extension), which `_run` discards by
  /// only threading back `res.data`.
  Future<(List<int> bytes, String? contentType)> getBytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return (res.data ?? const <int>[], res.headers.value('content-type'));
    } on DioException catch (e) {
      final error = AppError.fromDio(e);
      if (!_raiseCourseBlock(e) && !error.isAuthError) _failures.value = error;
      throw error;
    }
  }

  /// Authenticated binary POST (a CSV export) — the body is JSON, the answer is a file.
  Future<List<int>> postBytes(String path, {Object? body}) async {
    try {
      final res = await _dio.post<List<int>>(
        path,
        data: body,
        options: Options(responseType: ResponseType.bytes),
      );
      return res.data ?? const <int>[];
    } on DioException catch (e) {
      final error = AppError.fromDio(e);
      if (!_raiseCourseBlock(e) && !error.isAuthError) _failures.value = error;
      throw error;
    }
  }

  /// Withdraws [error] from [failures] when the caller has already explained
  /// it on screen (a closing-note prompt, a "Changed elsewhere" message), so
  /// the shell's generic toast does not repeat it in raw form. Must be called
  /// within the shell's short coalescing window, i.e. straight from the catch.
  void handled(AppError error) {
    if (identical(_failures.value, error)) _failures.value = null;
  }

  Future<dynamic> _run(Future<Response<dynamic>> Function() call,
      {bool quiet = false, bool countsAsWrite = true}) async {
    try {
      final res = await call();
      if (countsAsWrite && res.requestOptions.method.toUpperCase() != 'GET') {
        _writes.value++;
      }
      final status = res.statusCode ?? 0;
      final hold = approvalEventOf(status, res.data);
      if (hold != null) _holds.value = hold;
      // A held save answers an envelope around the record; callers that read
      // the answer as the record get the record, with its gated fields still
      // as they were.
      return recordOf(status, res.data);
    } on DioException catch (e) {
      final error = AppError.fromDio(e);
      // Announced before the throw, so it is recorded even when the caller
      // swallows the exception — which is exactly what the best-effort fetches
      // and the optimistic notes composer do.
      //
      // 401 is deliberately excluded: it is the session expiring, which the
      // auth interceptor already handles by logging out, and a toast about it
      // would only add noise to that.
      final isWrite = e.requestOptions.method.toUpperCase() != 'GET';
      if (_raiseCourseBlock(e)) throw error;
      if (!quiet &&
          !error.isAuthError &&
          (isWrite || error.type == AppErrorType.forbidden)) {
        _failures.value = error;
      }
      throw error;
    }
  }
}

/// `If-Match` for an optimistic-lock write: the record's `updated_at` as last
/// read, quoted as an entity tag (the webapp's contract). Null — no header, so
/// last write wins as before — when the version is unknown.
Map<String, dynamic>? ifMatchHeaders(String? version) {
  final v = version?.trim() ?? '';
  if (v.isEmpty) return null;
  return {'If-Match': '"${v.replaceAll('"', '')}"'};
}
