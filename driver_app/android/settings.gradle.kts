pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    // 2.3.0, not the Flutter-generated 2.1.0: google_maps_flutter_android's
    // dependencies (android-maps-utils) are built against Kotlin 2.3.0 - a
    // metadata-version mismatch against an older plugin crashed the Kotlin
    // compiler outright (only visible once a real Android build runs, which
    // flutter analyze/flutter test never do). Matches user_app's same fix.
    id("org.jetbrains.kotlin.android") version "2.3.0" apply false
}

include(":app")
