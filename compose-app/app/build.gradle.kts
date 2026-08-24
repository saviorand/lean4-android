plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.leanandroid.compose"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.leanandroid.compose"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        ndk { abiFilters += "arm64-v8a" }
    }

    // The Lean runtime stores data in the top byte of pointers, which collides with
    // Android's heap pointer tagging; see android-probe/README.md. The opt-out lives
    // in the manifest, so it is set there rather than here.
    packaging {
        jniLibs {
            useLegacyPackaging = true   // extractNativeLibs: the .so is too large to mmap from the apk
        }
    }

    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = "11" }
    buildTypes {
        release { isMinifyEnabled = false }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
}
