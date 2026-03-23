import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.gastrocore.gastrocore_pos"
    // Explicit SDK versions — do not rely on flutter.* variables for release.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.gastrocore.gastrocore_pos"
        // Android 5.0 Lollipop (API 21) — covers >98% of active Android devices.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Ensure multidex is available on API 21 (needed for large Flutter apps).
        multiDexEnabled = true
    }

    // ---------------------------------------------------------------------------
    // Product Flavors
    // ---------------------------------------------------------------------------

    flavorDimensions += "app"

    productFlavors {
        // POS terminal flavor — the original tablet/counter application.
        create("pos") {
            dimension = "app"
            applicationId = "com.gastrocore.gastrocore_pos"
            resValue("string", "app_name", "GastroCore POS")
        }

        // Waiter flavor — mobile-optimised phone app for waitstaff.
        create("waiter") {
            dimension = "app"
            applicationId = "com.gastrocore.waiter"
            resValue("string", "app_name", "GastroCore Waiter")
        }

        // Kiosk flavor — customer-facing self-ordering app for kiosk hardware.
        create("kiosk") {
            dimension = "app"
            applicationId = "com.gastrocore.kiosk"
            resValue("string", "app_name", "GastroCore Kiosk")
        }

        // KDS flavor — wall-mounted kitchen display for cook stations.
        create("kds") {
            dimension = "app"
            applicationId = "com.gastrocore.kds"
            resValue("string", "app_name", "GastroCore KDS")
        }

        // ODS flavor — Order Display Screen shown to customers at the counter/TV.
        create("ods") {
            dimension = "app"
            applicationId = "com.gastrocore.ods"
            resValue("string", "app_name", "GastroCore Order Display")
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as? String ?: ""
            keyPassword = keyProperties["keyPassword"] as? String ?: ""
            storeFile = (keyProperties["storeFile"] as? String)?.let { rootProject.file(it) }
            storePassword = keyProperties["storePassword"] as? String ?: ""
        }
    }

    buildTypes {
        debug {
            // Debug builds get a different applicationId suffix so they can
            // be installed alongside the release build on the same device.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            isDebuggable = true
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            // proguard-android-optimize.txt enables aggressive R8 optimisations
            // on top of our custom rules.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

repositories {
    flatDir {
        dirs("libs")
    }
}

dependencies {
    implementation(files("libs/slavesdk2.1.8.aar"))
    implementation("androidx.gridlayout:gridlayout:1.0.0")
    // Multidex support for API 21 (Flutter apps exceed 64k method limit).
    implementation("androidx.multidex:multidex:2.0.1")
    // integration_test is a dev dependency but GeneratedPluginRegistrant.java references it
    // in all build modes due to a Flutter tool bug. Add it for release compilation only;
    // R8 will strip unused test code from the release APK.
    releaseImplementation(project(":integration_test"))
}
