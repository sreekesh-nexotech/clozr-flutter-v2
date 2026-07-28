import '../config/env.dart';

/// Builds the [Env] for this build and validates it.
///
/// Values come from compile-time constants, passed at build time:
///
/// ```bash
/// flutter run --dart-define=FLAVOR=dev \
///             --dart-define=API_BASE_URL=https://dev.api.clozr.app
/// ```
///
/// Compile-time defines are used rather than a bundled `.env` file because an
/// asset ships inside the APK and can be read back out — see Flutter Coding
/// Standards §9 ("hide API keys"). Secrets must never appear here either; this
/// carries hosts and switches only.
class EnvLoader {
  const EnvLoader._();

  // ── Define names ──

  /// `--dart-define` key selecting the flavour.
  static const String flavorKey = 'FLAVOR';

  /// `--dart-define` key carrying the API root URL.
  static const String apiBaseUrlKey = 'API_BASE_URL';

  /// `--dart-define` key overriding the connect timeout, in seconds.
  static const String connectTimeoutKey = 'CONNECT_TIMEOUT_SECONDS';

  /// `--dart-define` key overriding the receive timeout, in seconds.
  static const String receiveTimeoutKey = 'RECEIVE_TIMEOUT_SECONDS';

  // ── Defaults ──

  /// Flavour assumed when [flavorKey] is absent.
  static const String defaultFlavor = 'dev';

  /// Seconds to wait for a connection.
  static const int defaultConnectTimeoutSeconds = 15;

  /// Seconds to wait for a response body.
  static const int defaultReceiveTimeoutSeconds = 30;

  /// Resolves, validates and installs the environment.
  ///
  /// Returns the installed [Env]. Throws [StateError] with an actionable
  /// message when a required value is missing or malformed — failing loudly at
  /// startup rather than on the first API call.
  static Env load() {
    final flavor = _resolveFlavor(
      const String.fromEnvironment(flavorKey, defaultValue: defaultFlavor),
    );

    const rawBaseUrl = String.fromEnvironment(apiBaseUrlKey);
    final baseUrl = _validateBaseUrl(rawBaseUrl, flavor);

    const connectSeconds = int.fromEnvironment(
      connectTimeoutKey,
      defaultValue: defaultConnectTimeoutSeconds,
    );
    const receiveSeconds = int.fromEnvironment(
      receiveTimeoutKey,
      defaultValue: defaultReceiveTimeoutSeconds,
    );

    final env = Env(
      flavor: flavor,
      apiBaseUrl: baseUrl,
      connectTimeout: const Duration(seconds: connectSeconds),
      receiveTimeout: const Duration(seconds: receiveSeconds),
      enableNetworkLogging: !flavor.isProduction,
      enableCrashReporting: flavor != AppFlavor.dev,
    );

    Env.install(env);
    return env;
  }

  static AppFlavor _resolveFlavor(String raw) {
    final normalised = raw.trim().toLowerCase();
    for (final flavor in AppFlavor.values) {
      if (flavor.name == normalised) return flavor;
    }
    throw StateError(
      'Unknown $flavorKey "$raw". '
      'Expected one of: ${AppFlavor.values.map((f) => f.name).join(', ')}.',
    );
  }

  static String _validateBaseUrl(String raw, AppFlavor flavor) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw StateError(
        'Missing $apiBaseUrlKey for the ${flavor.displayName} build. '
        'Pass --dart-define=$apiBaseUrlKey=https://…',
      );
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('$apiBaseUrlKey "$raw" is not a valid absolute URL.');
    }

    // Standards §9: HTTPS everywhere. Plain HTTP is tolerated only on dev.
    if (uri.scheme != 'https' && flavor != AppFlavor.dev) {
      throw StateError(
        '$apiBaseUrlKey must use https on ${flavor.displayName} builds.',
      );
    }

    // Strip a trailing slash so path builders can assume none.
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
