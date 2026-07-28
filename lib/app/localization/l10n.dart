import 'dart:ui';

/// Locale configuration for the app.
///
/// NOT WIRED YET: `MaterialApp.router` in `app.dart` declares no
/// `localizationsDelegates` or `supportedLocales`, so every string still comes
/// from the widget that renders it and the UI is unchanged.
///
/// To finish the setup:
///  1. Add `flutter_localizations` (SDK) to `pubspec.yaml` and set
///     `flutter: generate: true`.
///  2. Add an `l10n.yaml` pointing at `lib/app/localization/arb`.
///  3. Run `flutter gen-l10n`, then expose the generated `AppLocalizations`
///     delegates from this class.
///  4. Migrate hard-coded strings feature by feature — that step changes UI
///     code, so it is deliberately not part of this scaffold.
// TODO(clozr): wire flutter_localizations + gen-l10n 2026-07-28
class L10n {
  const L10n._();

  /// English (India) — the design language and the only locale shipped today.
  static const Locale english = Locale('en');

  /// Malayalam — planned for the Kerala field-sales rollout.
  static const Locale malayalam = Locale('ml');

  /// Hindi — planned.
  static const Locale hindi = Locale('hi');

  /// Locales the app currently ships. Keep [english] first: it is the
  /// fallback when the device locale matches nothing here.
  static const List<Locale> supportedLocales = [english];

  /// Locales with translation files in progress, not yet shipped.
  static const List<Locale> plannedLocales = [malayalam, hindi];

  /// Resolves the device [locale] against [supportedLocales].
  ///
  /// Matches on language code only, so `en_GB` and `en_IN` both resolve to
  /// [english]. Falls back to [english] rather than returning null, so the app
  /// never renders untranslated keys.
  static Locale resolve(Locale? locale) {
    if (locale == null) return english;
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
    return english;
  }
}
