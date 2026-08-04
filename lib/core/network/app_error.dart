import 'package:dio/dio.dart';

/// Broad failure categories the UI can branch on (retry banner vs logout vs
/// inline validation).
enum AppErrorType {
  /// No connectivity / DNS / socket-level failure.
  network,

  /// Connect/send/receive timeout.
  timeout,

  /// 401 after the refresh-and-retry cycle — session is gone.
  unauthorized,

  /// 403 — authenticated but not allowed (RBAC / plan gate / mandate gate).
  forbidden,

  /// 404.
  notFound,

  /// 400/422 — request understood but rejected; [fieldErrors] may be set.
  validation,

  /// 429 — throttled / account lockout.
  throttled,

  /// 5xx.
  server,

  /// Request was cancelled by the caller.
  cancelled,

  /// Anything else (parse failures included).
  unknown,
}

/// The single failure model that crosses the repository boundary. Data sources
/// throw [AppError]; providers surface `AsyncError<AppError>`; widgets render
/// [message] and never see Dio types.
class AppError implements Exception {
  const AppError({
    required this.type,
    required this.message,
    this.statusCode,
    this.fieldErrors,
    this.cause,
  });

  final AppErrorType type;

  /// Human-readable message, already safe to show in a toast/empty state.
  final String message;

  final int? statusCode;

  /// DRF field-level validation errors: `{field: [messages]}`.
  final Map<String, List<String>>? fieldErrors;

  /// The underlying exception, for logs only — never shown to the user.
  final Object? cause;

  bool get isAuthError => type == AppErrorType.unauthorized;

  /// Maps a [DioException] (and the DRF error body conventions) onto the
  /// app-level model. DRF errors arrive as `{"detail": "..."}`,
  /// `{"error": "..."}`, `{"message": "..."}` or `{field: ["msg", ...]}`.
  factory AppError.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppError(
          type: AppErrorType.timeout,
          message: 'The server took too long to respond. Please try again.',
          cause: e,
        );
      case DioExceptionType.connectionError:
        return AppError(
          type: AppErrorType.network,
          message: 'No internet connection. Check your network and retry.',
          cause: e,
        );
      case DioExceptionType.cancel:
        return AppError(
          type: AppErrorType.cancelled,
          message: 'Request cancelled.',
          cause: e,
        );
      case DioExceptionType.badResponse:
        return AppError._fromResponse(e);
      default:
        return AppError(
          type: AppErrorType.unknown,
          message: 'Something went wrong. Please try again.',
          cause: e,
        );
    }
  }

  factory AppError._fromResponse(DioException e) {
    final status = e.response?.statusCode ?? 0;
    final body = e.response?.data;
    final message = _extractMessage(body) ?? _defaultMessage(status);
    return AppError(
      type: _typeForStatus(status),
      message: message,
      statusCode: status,
      fieldErrors: _extractFieldErrors(body),
      cause: e,
    );
  }

  static AppErrorType _typeForStatus(int status) {
    if (status == 401) return AppErrorType.unauthorized;
    if (status == 403) return AppErrorType.forbidden;
    if (status == 404) return AppErrorType.notFound;
    if (status == 429) return AppErrorType.throttled;
    if (status == 400 || status == 422) return AppErrorType.validation;
    if (status >= 500) return AppErrorType.server;
    return AppErrorType.unknown;
  }

  static String _defaultMessage(int status) {
    if (status == 401) return 'Your session has expired. Please sign in again.';
    if (status == 403) return "You don't have permission to do that.";
    if (status == 404) return 'Not found.';
    if (status == 429) return 'Too many attempts. Please wait and try again.';
    if (status >= 500) return 'Server error. Please try again shortly.';
    return 'Something went wrong. Please try again.';
  }

  /// Pulls the first human-readable string out of an error body.
  ///
  /// The backend's exception handler emits `{code, message}` (plus `errors`
  /// for 400 validation); raw DRF shapes (`detail` / field maps) can still
  /// appear from middleware paths, so both are handled.
  static String? _extractMessage(Object? body) {
    if (body is String && body.trim().isNotEmpty && !body.startsWith('<')) {
      return body;
    }
    if (body is Map) {
      // A 400 whose `message` is the generic "Validation Error" is less
      // useful than the first concrete field error — prefer the latter.
      final message = body['message'];
      final fieldErrors = _extractFieldErrors(body);
      if (message is String &&
          message.isNotEmpty &&
          (message != 'Validation Error' || fieldErrors == null)) {
        return message;
      }
      for (final key in const ['detail', 'error', 'non_field_errors']) {
        final v = body[key];
        if (v is String && v.isNotEmpty) return v;
        if (v is List && v.isNotEmpty && v.first is String) {
          return v.first as String;
        }
      }
      if (fieldErrors != null && fieldErrors.isNotEmpty) {
        final first = fieldErrors.entries.first;
        return first.key == 'non_field_errors'
            ? first.value.first
            : '${first.key}: ${first.value.first}';
      }
      if (message is String && message.isNotEmpty) return message;
    }
    return null;
  }

  static Map<String, List<String>>? _extractFieldErrors(Object? body) {
    if (body is! Map) return null;
    // The handler nests field errors under `errors`; raw DRF puts them at the
    // top level.
    final source = body['errors'] is Map ? body['errors'] as Map : body;
    final out = <String, List<String>>{};
    for (final entry in source.entries) {
      final key = entry.key.toString();
      if (const {'detail', 'error', 'message', 'code', 'error_codes'}.contains(key)) {
        continue;
      }
      final v = entry.value;
      if (v is List) {
        final msgs = v.whereType<String>().toList();
        if (msgs.isNotEmpty) out[key] = msgs;
      } else if (v is String) {
        out[key] = [v];
      }
    }
    return out.isEmpty ? null : out;
  }

  @override
  String toString() => 'AppError($type, $statusCode): $message';
}
