import java.util.Properties
import java.io.FileInputStream
// 1. Khởi tạo Properties và xác định file
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
// 2. Chỉ load nếu file tồn tại (Ở Local)
val isLocalSigningReady = if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    keystoreProperties.containsKey("keyAlias") && 
    keystoreProperties.containsKey("keyPassword") &&
    keystoreProperties.containsKey("storeFile") && 
    keystoreProperties.containsKey("storePassword")
} else {
    false
}
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.tqtrung.novelread.novel_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        // BẬT DESUGARING ĐỂ FIX LỖI OTA_UPDATE
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
    defaultConfig {
        applicationId = "com.tqtrung.novelread.novel_app"
        // Đảm bảo minSdk ít nhất là 21 để hỗ trợ đa số thư viện hiện nay
        minSdk = flutter.minSdkVersion 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Cần thiết khi bật Desugaring
        multiDexEnabled = true
    }
    signingConfigs {
        if (isLocalSigningReady) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = if (isLocalSigningReady) {
                signingConfigs.getByName("release")
            } else {
                null
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this as com.android.build.gradle.internal.api.ApkVariantOutputImpl
            output.versionCodeOverride = variant.versionCode
        }
    }
}
dependencies {
    // THÊM THƯ VIỆN DESUGAR JDK LIBS
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
flutter {
    source = "../.."
}
