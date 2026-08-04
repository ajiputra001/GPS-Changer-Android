import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Local signing credentials (gitignored — see android/key.properties.example).
// CI supplies STORE_PASSWORD/KEY_PASSWORD/KEY_ALIAS as env vars instead.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.ajiputratech.gpsmock"
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
        applicationId = "com.ajiputratech.gpsmock"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val kFile = file(keystoreProperties.getProperty("storeFile") ?: "upload-keystore.jks")
            if (kFile.exists()) {
                storeFile = kFile
                storePassword = keystoreProperties.getProperty("storePassword")?.takeIf { it.isNotBlank() }
                    ?: System.getenv("STORE_PASSWORD")?.takeIf { it.isNotBlank() }
                    ?: "android"
                keyAlias = keystoreProperties.getProperty("keyAlias")?.takeIf { it.isNotBlank() }
                    ?: System.getenv("KEY_ALIAS")?.takeIf { it.isNotBlank() }
                    ?: "upload"
                keyPassword = keystoreProperties.getProperty("keyPassword")?.takeIf { it.isNotBlank() }
                    ?: System.getenv("KEY_PASSWORD")?.takeIf { it.isNotBlank() }
                    ?: "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
