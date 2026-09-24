plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

android {
    namespace = "com.aichar.ai_character_app"
    compileSdk = 37
    // 不强制指定 NDK 版本，避免本机未装对应 NDK 时长时间下载

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aichar.ai_character_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val jpushProps = Properties()
        val jpushFile = rootProject.file("jpush.properties")
        if (jpushFile.exists()) {
            jpushProps.load(jpushFile.inputStream())
        }
        val jpushAppKey = (
            jpushProps.getProperty("JPUSH_APPKEY", "").trim().ifEmpty {
                System.getenv("JPUSH_APPKEY")?.trim().orEmpty()
            }
        )
        if (jpushAppKey.isEmpty()) {
            println("WARN: JPUSH_APPKEY 为空，请配置 android/jpush.properties 或环境变量 JPUSH_APPKEY")
        }
        manifestPlaceholders["JPUSH_PKGNAME"] = applicationId!!
        manifestPlaceholders["JPUSH_APPKEY"] = jpushAppKey
        manifestPlaceholders["JPUSH_CHANNEL"] = "ai-character"
    }

    buildTypes {
        release {
            // 开发侧载用 debug 签名；不可上架商店
            signingConfig = signingConfigs.getByName("debug")
            // 侧载联调包关闭压缩混淆，避免缺 Play Core 依赖导致 R8 失败
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    val media3 = "1.4.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-ui:$media3")
}
