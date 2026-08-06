plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.clozrapp"

    // Pinned above Flutter's defaults because the plugins pinned in
    // `pubspec.lock` demand it. Both are backward compatible, so the rule is
    // "the highest any plugin asks for":
    //   * `flutter_plugin_android_lifecycle` 2.0.35 and `url_launcher_android`
    //     6.3.32 are compiled against SDK 36; a project on 34 cannot consume
    //     them.
    //   * `file_picker`, `flutter_secure_storage`, `path_provider_android` and
    //     the two above all want NDK 27, against Flutter's default 23.
    // An older checkout may only be told it needs 35 — that is a stale lock,
    // not a different answer. Revisit when Flutter's own defaults catch up.
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.clozrapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
