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
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tryo.healthassistant"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
            val keystoreProperties = java.util.Properties()
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
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

flutter {
    source = "../.."
}
