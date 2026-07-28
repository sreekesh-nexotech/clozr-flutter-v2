import '../error/failure.dart';

/// Translates transport-level errors into the [Failure] hierarchy.
///
/// Deliberately free of any HTTP-package types so the mapping can be unit
/// tested without a client, and so swapping Dio for something else touches
/// only `api_client.dart`. Repositories call this; widgets never do.
class NetworkExceptions {
  const NetworkExceptions._();

  // ── Status codes (named so no magic numbers leak into the mapping) ──

  /// The request was malformed.
  static const int badRequest = 400;

  /// The session is missing or expired.
  static const int unauthorised = 401;

  /// The session is valid but lacks permission.
  static const int forbidden = 403;

  /// The resource does not exist.
  static const int notFound = 404;

  /// The payload failed server-side validation.
  static const int unprocessable = 422;

  /// The client is being rate limited.
  static const int tooManyRequests = 429;

  /// Lowest status treated as a server-side fault.
  static const int internalServerError = 500;

  /// Maps an HTTP [statusCode] to the matching [Failure].
  ///
  /// [serverMessage] is used verbatim when the backend supplies a user-safe
  /// string; otherwise a generic fallback is returned so raw server text is
  /// never shown to the user.
  static Failure fromStatusCode(
    int statusCode, {
    String? serverMessage,
    Object? cause,
  }) {
    final message = serverMessage?.trim();
    final hasMessage = message != null && message.isNotEmpty;

    switch (statusCode) {
      case unauthorised:
      case forbidden:
        return AuthFailure(
          hasMessage ? message : 'Your session has expired. Please sign in.',
          cause: cause,
        );
      case notFound:
        return NotFoundFailure(
          hasMessage ? message : 'That record no longer exists.',
          cause: cause,
        );
      case badRequest:
      case unprocessable:
        return ValidationFailure(
          hasMessage ? message : 'Please check the details and try again.',
          cause: cause,
        );
      case tooManyRequests:
        return const ServerFailure(
          'Too many requests. Please wait a moment.',
          statusCode: tooManyRequests,
        );
      default:
        if (statusCode >= internalServerError) {
          return ServerFailure(
            'Something went wrong on our side. Please try again.',
            statusCode: statusCode,
            cause: cause,
          );
        }
        return ServerFailure(
          hasMessage ? message : 'Request failed.',
          statusCode: statusCode,
          cause: cause,
        );
    }
  }

  /// Maps a thrown [error] with no HTTP status (socket, timeout, decode).
  static Failure fromError(Object error) {
    if (error is Failure) return error;
    if (error is FormatException) {
      return ParseFailure('Unexpected response from the server.', cause: error);
    }
    return UnknownFailure('Something went wrong. Please try again.',
        cause: error);
  }
}
