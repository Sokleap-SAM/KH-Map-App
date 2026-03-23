import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val envProperties = Properties()
val envFile = rootProject.file("../.env")
if (envFile.exists()) {
    envFile.inputStream().use { stream ->
        envProperties.load(stream)
    }
} else {
    println("WARNING: .env file not found at ${envFile.absolutePath}")
}

android {
    namespace = "com.example.kh_map_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.kh_map_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion //min sdk = 24+
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val apiKey = envProperties.getProperty("GOOGLE_MAPS_API_KEY", "")
        println("DEBUG: Google Maps API Key loaded: ${if (apiKey.isNotEmpty()) apiKey.substring(0, 10) + "..." else "EMPTY!"}")
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = apiKey
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
