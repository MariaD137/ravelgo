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
    // 2.3.0, not the Flutter-generated 2.1.0: amplify_push_notifications pulls
    // in kotlin-stdlib/kotlinx-serialization built against Kotlin 2.3.0 —
    // compiling this app's own Kotlin against an older plugin version hit a
    // hard metadata-version mismatch (a real Android Gradle build failure,
    // invisible to `flutter analyze`/`flutter test`, which never run Gradle).
    id("org.jetbrains.kotlin.android") version "2.3.0" apply false
}

include(":app")
