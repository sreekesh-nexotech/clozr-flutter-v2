import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material. `key.properties` is gitignored (see
// android/.gitignore) — copy key.properties.example and fill it in. Without it
// the release build falls back to debug keys, which Play rejects, so the
// fallback shouts rather than passing silently.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) keystorePropertiesFile.inputStream().use { load(it) }
}

android {
    namespace = "com.nexotech.clozrapp"

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
        // Permanent once published — Play ties the listing, reviews and install
        // base to this string and it can never be changed for the same app.
        applicationId = "com.nexotech.clozrapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Pinned, not inherited. `flutter.minSdkVersion` is 21 on the SDK this
        // project pins (3.24.5), and Play refuses the upload outright: "Play
        // automatic protection requires a minimum SDK version of 24 or higher.
        // The uploaded App Bundle has a minimum SDK version of 21." Nothing in
        // `pubspec.lock` asks for more than 21, so 24 is the binding floor.
        // Raising the Flutter pin would change this number silently, so it is
        // stated here instead — same reasoning as targetSdk below.
        minSdk = 24
        // Pinned, not inherited. `flutter.targetSdkVersion` is 34 on the SDK
        // this project pins (3.24.5), and Play rejects anything below 36:
        // "Your app currently targets API level 34 and must target at least
        // API level 36". Raising the Flutter pin would change this number
        // silently, so it is stated here instead.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // `flutter run --release` still works on a dev machine; an
                // artifact built this way can never be uploaded to Play.
                // `println` rather than `logger.warn` on purpose — Flutter's
                // Gradle wrapper filters warn-level output, and a silently
                // debug-signed release is the whole failure mode this guards.
                println(
                    "\n**************************************************************\n" +
                    "  android/key.properties not found - signing with DEBUG keys.\n" +
                    "  This build CANNOT be uploaded to the Play Store.\n" +
                    "  See android/key.properties.example to set up signing.\n" +
                    "**************************************************************\n"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
