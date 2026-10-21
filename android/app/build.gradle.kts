plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nuans.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Placeholder until the real owned domain is registered; recorded as
        // assumption A3 and on the release checklist in docs/ci-cd.md.
        applicationId = "com.nuans.app"

        // Android 10. The capture protocol needs MANUAL_SENSOR and RAW_SENSOR,
        // and the Camera2 metadata the exposure solver reads - dynamic black
        // level in particular - is only dependable from this level up. A
        // device below it could run the app but not the measurement, which
        // would be worse than not installing.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // The real upload key arrives from CI through android/key.properties
            // (see docs/ci-cd.md). Until then a release build is debug-signed,
            // which installs on a phone and cannot be uploaded to Play - which
            // is the right way round for a build nobody has reviewed.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
