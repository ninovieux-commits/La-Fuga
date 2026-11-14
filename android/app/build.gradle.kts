import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// LA CLÉ DE PUBLICATION, quand elle est là.
//
// `android/key.properties` nomme la clé et dit ses mots de passe ; il est
// ignoré par git, comme le fichier `.jks` lui-même — le dépôt est public.
// Absent, on signe avec la clé de debug : un APK de test se compile sans
// aucun secret, ici comme sur GitHub, et c'est ce qui fait tourner la
// compilation à chaque commit.
//
// Un APK signé par la clé de debug ne peut PAS être publié, et Google ne
// l'accepterait pas : la clé de debug est la même pour tout le monde.
val fichierDeCle = rootProject.file("key.properties")
val cle = Properties().apply {
    if (fichierDeCle.exists()) FileInputStream(fichierDeCle).use { load(it) }
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

    signingConfigs {
        create("publication") {
            if (fichierDeCle.exists()) {
                keyAlias = cle.getProperty("keyAlias")
                keyPassword = cle.getProperty("keyPassword")
                storeFile = file(cle.getProperty("storeFile"))
                storePassword = cle.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (fichierDeCle.exists()) {
                signingConfigs.getByName("publication")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
