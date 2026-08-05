/// Compile-time API configuration.
///
/// The base URL is injected with `--dart-define` so no environment secrets
/// live in source control:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=https://api.example.com
/// ```
///
/// When [baseUrl] is empty the app runs in **mock mode**: every repository
/// serves the bundled seed data exactly as the presentation build did, so
/// designers/QA can keep using the app without a backend.
class ApiConfig {
  ApiConfig._();

  /// Backend origin, e.g. `https://crm.example.com`. No trailing slash.
  ///
  /// Defaults to the dev backend so a plain `flutter run` talks to a real API;
  /// `--dart-define=API_BASE_URL=…` still overrides it per build (pass an empty
  /// value, or `--dart-define=USE_MOCK_DATA=true`, to get mock mode back).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dev.clozr.tech',
  );

  /// All REST routes mount under this prefix on the backend.
  static const String apiPrefix = '/api/v1';

  /// Force mock data even when a base URL is configured (demo/QA builds).
  static const bool forceMocks = bool.fromEnvironment('USE_MOCK_DATA');

  /// Whether the remote data sources should be wired in.
  static bool get apiEnabled => baseUrl.isNotEmpty && !forceMocks;

  /// True when the configured base URL uses TLS, or points at a local dev host
  /// (loopback / Android emulator) where cleartext is acceptable in debug.
  static bool get isBaseUrlSecure {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return false;
    if (uri.scheme == 'https') return true;
    const localHosts = {'localhost', '127.0.0.1', '10.0.2.2', '::1'};
    return uri.scheme == 'http' && localHosts.contains(uri.host);
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  /// Server page size ceiling is 200; the mobile lists load in pages of 50.
  static const int defaultPageSize = 50;
}
