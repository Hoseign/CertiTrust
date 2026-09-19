plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.certitrust.app.certitrust_mobile"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.certitrust.app.certitrust_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
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

// Safely force subprojects to compile against SDK 36 to satisfy file_picker / lifecycle requirements
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android")
        if (androidExtension != null) {
            try {
                val method = androidExtension.javaClass.getMethod("compileSdk", Int::class.java)
                method.invoke(androidExtension, 36)
            } catch (e: Exception) {
                try {
                    val method = androidExtension.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
                    method.invoke(androidExtension, 36)
                } catch (ignored: Exception) {
                }
            }
        }
    }
}