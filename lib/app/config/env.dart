/// Build flavours the app ships in.
enum AppFlavor {
  /// Local / developer builds against the dev backend.
  dev,

  /// Pre-production builds for QA sign-off.
  staging,

  /// Store builds.
  prod,
}

/// Display helpers for [AppFlavor].
extension AppFlavorX on AppFlavor {
  /// Label shown in debug banners and diagnostics screens.
  String get displayName => switch (this) {
        AppFlavor.dev => 'Dev',
        AppFlavor.staging => 'Staging',
        AppFlavor.prod => 'Production',
      };

  /// Whether this is the store build. Gates logging and debug affordances.
  bool get isProduction => this == AppFlavor.prod;
}

/// The resolved environment for the running app.
///
/// Built once at startup by `EnvLoader` and read through [current] — e.g.
/// `Env.current.apiBaseUrl`. Immutable, so nothing can reconfigure the app
/// mid-session.
class Env {
  /// Creates an environment description.
  const Env({
    required this.flavor,
    required this.apiBaseUrl,
    required this.connectTimeout,
    required this.receiveTimeout,
    this.enableNetworkLogging = false,
    this.enableCrashReporting = true,
  });

  /// Which backend and configuration this build targets.
  final AppFlavor flavor;

  /// Root URL for every API call, without a trailing slash.
  final String apiBaseUrl;

  /// How long to wait for a connection before failing.
  final Duration connectTimeout;

  /// How long to wait for a response body before failing.
  final Duration receiveTimeout;

  /// Whether to attach a verbose HTTP logger. Never enable in production.
  final bool enableNetworkLogging;

  /// Whether crashes and non-fatal errors are reported upstream.
  final bool enableCrashReporting;

  static Env? _current;

  /// The active environment.
  ///
  /// Throws [StateError] when read before `EnvLoader.load()` has installed
  /// one — a loud failure at startup beats silently calling the wrong host.
  static Env get current {
    final env = _current;
    if (env == null) {
      throw StateError(
        'Env.current read before initialisation. '
        'Call EnvLoader.load() in bootstrap() first.',
      );
    }
    return env;
  }

  /// Whether an environment has been installed yet.
  static bool get isInitialised => _current != null;

  /// Installs [env] as the active environment. Called once, from bootstrap.
  static void install(Env env) => _current = env;

  /// Clears the installed environment. Test-only.
  static void reset() => _current = null;
}
