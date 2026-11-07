import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase (google-services.json is in android/app/).
    id("com.google.gms.google-services")
}

android {
    namespace = "com.tryo.healthassistant"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Flag to enable support for the new language APIs
        isCoreLibraryDesugaringEnabled = true
        // Sets Java compatibility to Java 17
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tryo.healthassistant"
        // 26, not flutter.minSdkVersion (24): the `health` package
        // (Health Connect) declares minSdk 26 and the manifest merger
        // fails below it. Safe for the target phone (Android 13+).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // Stable committed debug keystore (android/app/debug.keystore, PKCS12,
    // standard debug credentials) so every CI build signs with the same key.
    // Its SHA-1 must stay registered in Firebase or Google sign-in breaks.
    signingConfigs {
        // Note: use getByName("debug") — the bare `debug { }` accessor does
        // not resolve on the signing-config container in Kotlin DSL.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
            storeType = "PKCS12"
        }
        // Release keystore: android/key.properties (NOT committed — CI
        // creates it from GitHub secrets) + android/app/release.keystore
        // (decoded from the RELEASE_KEYSTORE_BASE64 secret). Its SHA-1
        // must be registered in Firebase or Google sign-in breaks.
        // Falls back to the debug key so `flutter run --release` still
        // works locally without the release keystore present.
        create("release") {
            val keystoreProperties = Properties()
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
            }
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null && file(storeFilePath).exists()) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeType = "PKCS12"
            } else {
                storeFile = file("debug.keystore")
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
                storeType = "PKCS12"
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // flutter_local_notifications (v10+) needs desugaring for scheduled
    // notifications (java.time APIs on older Android).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Health Connect client — MainActivity requests permissions directly
    // via the official API (same version the `health` plugin uses).
    implementation("androidx.health.connect:connect-client:1.2.0-alpha02")
}

flutter {
    source = "../.."
}
