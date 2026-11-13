import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase project configuration for push notifications (FCM).
///
/// The backend sends pushes through the Firebase project `nexocrm-bb56a`
/// (`FIREBASE_CRED_PATH` in the API's settings). This file is what
/// `flutterfire configure` would generate for that project; the Android and
/// iOS apps have to be registered in the Firebase console first, which is
/// where the `appId` / `messagingSenderId` values below come from.
///
/// Until those values are filled in, [isConfigured] is false and the app
/// skips Firebase entirely: no crash, no permission prompt, no device
/// registration — the in-app notification banner still works off the
/// existing 60-second unread poll.
///
/// To fill this in, either run `dart run flutterfire_cli:flutterfire
/// configure --project=nexocrm-bb56a` and copy the generated values here, or
/// read them off the Firebase console → Project settings → Your apps.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static const _placeholder = 'REPLACE_ME';

  /// Shared across the project's apps.
  static const String projectId = 'nexocrm-bb56a';

  /// Firebase console → Project settings → Cloud Messaging → Sender ID
  /// (also the GCP project number).
  static const String messagingSenderId = '267679337763';

  /// Android app `com.nexotech.clozrapp` — values from
  /// `android/app/google-services.json`.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAW1hN3X8d9S3CJc_yicu2qmyivdJVvs9U',
    appId: '1:267679337763:android:9fb9ae60b0b159ecf21096',
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: '$projectId.firebasestorage.app',
  );

  /// iOS app `com.nexotech.clozrapp` — values from
  /// `ios/Runner/GoogleService-Info.plist`.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDFuqxcY4XZffkcSY_uYsS5mJ5im_-qMfI',
    appId: '1:267679337763:ios:6d85ffce913169d8f21096',
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: '$projectId.firebasestorage.app',
    iosBundleId: 'com.nexotech.clozrapp',
  );

  static FirebaseOptions get currentPlatform =>
      Platform.isIOS || Platform.isMacOS ? ios : android;

  /// Whether this platform's app has real Firebase values. False means push
  /// is switched off for the build.
  static bool get isConfigured {
    final o = currentPlatform;
    return o.apiKey != _placeholder &&
        o.appId != _placeholder &&
        o.messagingSenderId != _placeholder;
  }
}
