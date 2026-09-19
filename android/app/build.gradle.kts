plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.lafuga.lafuga"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Exigé par flutter_local_notifications : rend les API java.time
        // disponibles sous Android 8. Sans cela, :app:checkDebugAarMetadata
        // refuse la dépendance.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Identique au couple package.domain + package.name de buildozer.spec,
        // pour que l'APK Flutter remplace l'APK Kivy sur le téléphone.
        applicationId = "org.lafuga.lafuga"
        minSdk = 24  // = android.minapi de buildozer.spec
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signé avec la clé de debug pour l'instant, comme le faisait
            // buildozer. À remplacer par une vraie clé avant publication.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
