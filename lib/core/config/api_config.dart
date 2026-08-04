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
  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  /// All REST routes mount under this prefix on the backend.
  static const String apiPrefix = '/api/v1';

  /// Force mock data even when a base URL is configured (demo/QA builds).
  static const bool forceMocks = bool.fromEnvironment('USE_MOCK_DATA');

  /// Whether the remote data sources should be wired in.
  static bool get apiEnabled => baseUrl.isNotEmpty && !forceMocks;

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  /// Server page size ceiling is 200; the mobile lists load in pages of 50.
  static const int defaultPageSize = 50;
}
