import 'package:equatable/equatable.dart';

/// Base type for every expected, recoverable error in the app.
///
/// Repositories catch transport / storage / parsing exceptions and translate
/// them into a [Failure] subtype, so the application and presentation layers
/// never see a `DioException`, a `HiveError` or a raw [FormatException].
/// Required by Flutter Coding Standards §5.2 ("Standard Error Model").
sealed class Failure extends Equatable implements Exception {
  /// Creates a failure carrying a user-safe [message] and the original [cause].
  const Failure(this.message, {this.cause});

  /// Human-readable, user-safe description. Never embed tokens or PII here.
  final String message;

  /// The originating exception, kept for logging and crash reporting only.
  final Object? cause;

  @override
  List<Object?> get props => [message, cause];

  @override
  String toString() => '$runtimeType: $message';
}

/// The request reached the backend but it answered with a non-2xx status.
class ServerFailure extends Failure {
  /// Creates a server failure for the given [statusCode].
  const ServerFailure(super.message, {this.statusCode, super.cause});

  /// HTTP status returned by the backend, when one was received.
  final int? statusCode;

  @override
  List<Object?> get props => [...super.props, statusCode];
}

/// No usable connection, DNS failure, or the request timed out.
class NetworkFailure extends Failure {
  /// Creates a connectivity failure.
  const NetworkFailure(super.message, {super.cause});
}

/// The session is missing, expired, or was rejected (HTTP 401 / 403).
///
/// The auth interceptor should attempt one refresh-and-retry before this
/// surfaces; if it still fails the app must log the user out.
class AuthFailure extends Failure {
  /// Creates an authentication/authorisation failure.
  const AuthFailure(super.message, {super.cause});
}

/// The backend rejected the payload (HTTP 422 and friends).
class ValidationFailure extends Failure {
  /// Creates a validation failure with optional per-field messages.
  const ValidationFailure(
    super.message, {
    this.fieldErrors = const {},
    super.cause,
  });

  /// Field name to error message, ready to drive `AppTextField.errorText`.
  final Map<String, String> fieldErrors;

  @override
  List<Object?> get props => [...super.props, fieldErrors];
}

/// A local cache read or write failed (Hive box missing, corrupt, or locked).
class CacheFailure extends Failure {
  /// Creates a local-storage failure.
  const CacheFailure(super.message, {super.cause});
}

/// The response was not valid JSON, or did not match the expected shape.
class ParseFailure extends Failure {
  /// Creates a deserialisation failure.
  const ParseFailure(super.message, {super.cause});
}

/// The requested resource does not exist (HTTP 404).
class NotFoundFailure extends Failure {
  /// Creates a not-found failure.
  const NotFoundFailure(super.message, {super.cause});
}

/// Anything that could not be classified into the cases above.
class UnknownFailure extends Failure {
  /// Creates an unclassified failure.
  const UnknownFailure(super.message, {super.cause});
}
