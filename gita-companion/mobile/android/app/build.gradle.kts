import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (docs/RELEASE.md): android/key.properties locally, or
// GITA_KEYSTORE / GITA_KEYSTORE_PASSWORD / GITA_KEY_ALIAS / GITA_KEY_PASSWORD
// in CI. The key itself is never in the repository.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun signingValue(property: String, env: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(env)?.takeIf { it.isNotEmpty() }

val releaseKeystore = signingValue("storeFile", "GITA_KEYSTORE")

android {
    namespace = "app.gitacompanion.gita_companion"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.gitacompanion.gita_companion"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseKeystore != null) {
                storeFile = file(releaseKeystore)
                storePassword = signingValue("storePassword", "GITA_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "GITA_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "GITA_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Signed with the release key when one is configured; otherwise
            // with the debug key, so a local test build still installs.
            signingConfig = signingConfigs.getByName(if (releaseKeystore != null) "release" else "debug")
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
