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
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.gastrocore.gastrocore_pos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
            keyAlias = keyProperties["keyAlias"]?.toString() ?: ""
            keyPassword = keyProperties["keyPassword"]?.toString() ?: ""
            storeFile = keyProperties["storeFile"]?.let { rootProject.file(it.toString()) }
            storePassword = keyProperties["storePassword"]?.toString() ?: ""
        }
    }

    buildTypes {
        release {
            // Use release signing when key.properties is present, debug signing otherwise.
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
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
    // MyPOS Slave SDK — Rota production kit (2026-05-13), supersedes the
    // previous local 2.1.8 AAR. Same SDK family but newer patches; ships
    // POSHandler, PaymentParams, OperationActivity, etc., plus the
    // TCP/IP auto-reconnect fix the kit's troubleshooting doc references.
    implementation(files("libs/slavesdk-release.aar"))
    implementation("androidx.gridlayout:gridlayout:1.0.0")
    // integration_test is a dev dependency but GeneratedPluginRegistrant.java references it
    // in all build modes due to a Flutter tool bug. Add it for release compilation only;
    // R8 will strip unused test code from the release APK.
    releaseImplementation(project(":integration_test"))
}
