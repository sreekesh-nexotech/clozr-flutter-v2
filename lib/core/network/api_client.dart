/// The single HTTP entry point for the whole app.
///
/// Flutter Coding Standards §6.1: every network call goes through one client,
/// and repositories are the only callers — never a provider, controller or
/// widget.
///
/// This is the transport-agnostic contract. The concrete `DioApiClient`
/// (interceptors, session-cookie handling, 401 refresh-and-retry, retry with
/// backoff, `pretty_dio_logger` in debug) lands with the integration PR — it
/// needs `dio`, `retrofit` and `pretty_dio_logger`, which are listed in
/// docs-flutter/Technical_stack.md but are not dependencies yet.
///
/// Implementations must translate every transport error through
/// `NetworkExceptions` so callers only ever see a `Failure`.
// TODO(clozr): add DioApiClient once dio is a dependency 2026-07-28
abstract interface class ApiClient {
  /// Issues a GET and returns the decoded JSON body.
  Future<dynamic> getAsync(
    String path, {
    Map<String, dynamic>? queryParameters,
  });

  /// Issues a POST with an optional JSON [body].
  Future<dynamic> postAsync(String path, {Object? body});

  /// Issues a PUT with an optional JSON [body].
  Future<dynamic> putAsync(String path, {Object? body});

  /// Issues a PATCH with an optional JSON [body].
  Future<dynamic> patchAsync(String path, {Object? body});

  /// Issues a DELETE.
  Future<dynamic> deleteAsync(String path);
}
