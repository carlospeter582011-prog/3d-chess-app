plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "__PKG__"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

    defaultConfig {
        applicationId = "__PKG__"
        minSdk = 23          // Android 6.0; device must support OpenGL ES 3.0 and arm64
        targetSdk = 36       // Google Play requires API 36 for new apps and updates from 31 Aug 2026
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters += listOf("arm64-v8a") }   // nearly all current phones; add "armeabi-v7a" / "x86_64" if you need them
    }

    // Release signing comes from the environment (GitHub Actions secrets) and is NEVER stored in the repository.
    // Without it the release build falls back to the debug key: fine for sideload testing, NOT accepted by Google Play.
    val keystoreFile = System.getenv("CHESS_KEYSTORE_FILE")?.takeIf { it.isNotBlank() }?.let { file(it) }
    val hasReleaseKey = keystoreFile != null && keystoreFile.exists()
    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = keystoreFile
                storePassword = System.getenv("CHESS_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CHESS_KEY_ALIAS")
                keyPassword = System.getenv("CHESS_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs {
            pickFirsts += listOf("**/libc++_shared.so")
            // arm64 only (the Filament AARs ship every ABI and abiFilters alone does not drop them)
            excludes += listOf("lib/x86/**", "lib/x86_64/**", "lib/armeabi-v7a/**")
        }
    }
}

flutter { source = "../.." }

dependencies {
    // 3D renderer + glTF loader (native code, Apache-2.0)
    implementation("com.google.android.filament:filament-android:__FILAMENT__")
    implementation("com.google.android.filament:gltfio-android:__FILAMENT__")
    implementation("androidx.core:core-ktx:1.13.1")
}
