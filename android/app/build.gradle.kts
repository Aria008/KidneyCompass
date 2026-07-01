plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.kidneycompass"
    ndkVersion = "27.0.12077973"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.kidneycompass"
        minSdk = 24  // Compatible with your OPPO A9 2020 (Android 11)
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    dependencies {
        implementation("com.google.android.gms:play-services-auth:20.7.0")
        implementation("com.google.android.gms:play-services-fitness:21.1.0")
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Apply Google Services plugin at the end
apply(plugin = "com.google.gms.google-services")
