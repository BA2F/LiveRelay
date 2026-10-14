import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式发布签名：android/key.properties（不入库）存在时启用 release 签名；
// 不存在时回退 debug 证书，保证无密钥环境仍可构建（产物不得对外发布）。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.liverelay.live_relay"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.liverelay.live_relay"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // local_auth 3.x and the biometric Keystore slot require Android 7+.
        minSdk = 24
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
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // Test builds have a separate Android sandbox and never overwrite
            // the installed user's production data or secure-storage slots.
            applicationIdSuffix = ".verification"
        }
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// 预编译 jniLibs 的 ABI 裁剪：buildTypes 级 ndk.abiFilters 对它们不生效，
// 需在 Variant API 上按构建类型排除。release 只留 arm64（32 位设备不再支持）；
// debug 保留 arm64（真机）与 x86_64（模拟器）。
androidComponents {
    onVariants(selector().all()) { variant ->
        when (variant.buildType) {
            "release" -> variant.packaging.jniLibs.excludes.addAll(
                listOf("lib/armeabi-v7a/**", "lib/x86_64/**"),
            )
            "debug" -> variant.packaging.jniLibs.excludes.add("lib/armeabi-v7a/**")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Same version already used by local_auth; direct dependency for our CryptoObject adapter.
    implementation("androidx.biometric:biometric:1.1.0")
    // Bundled on-device model: OCR never uploads the original image.
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}
