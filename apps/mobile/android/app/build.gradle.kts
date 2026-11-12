import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing from android/key.properties (kept out of git; CI writes it from secrets).
// Loaded outside `android {}`: inside it, `java` resolves to Gradle's Java extension, not the package.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

// Meta App Events ids from the same --dart-define values the Dart side reads (lib/core/config/env.dart),
// so the native SDK is configured exactly when its sink is registered. Flutter passes the defines as
// base64 in the `dart-defines` project property. Unset = empty = Meta stays off.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull { encoded ->
            runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }.getOrNull()
        }
        ?.mapNotNull { pair -> pair.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
        ?.toMap()
        ?: emptyMap()
// "fb" prefix: a numeric manifest value would be read as a number, which the Meta SDK rejects.
val facebookAppId = dartDefines["FACEBOOK_APP_ID"]?.trim().orEmpty().let { if (it.isEmpty()) "" else "fb$it" }
val facebookClientToken = dartDefines["FACEBOOK_CLIENT_TOKEN"]?.trim().orEmpty()

android {
    namespace = "com.yaqinbrand.yaqeen"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs java.time on older Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.yaqinbrand.yaqeen"
        // Android 7 (geolocator, secure storage, exact alarms) — covers the Egyptian device base.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["facebookAppId"] = facebookAppId
        manifestPlaceholders["facebookClientToken"] = facebookClientToken
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
