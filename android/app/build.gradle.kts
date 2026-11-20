plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.aurora.campo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.aurora.campo"
        // Android 8 em diante (Keystore com chave AES para o banco local e o cofre).
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Retorno do login no Keycloak (cliente aurora-campo, dev.aurora.campo:/oauthredirect).
        manifestPlaceholders["appAuthRedirectScheme"] = "dev.aurora.campo"
    }

    // Chave de publicação (Android Enterprise, app privado): só por variáveis de ambiente, nunca no repositório
    // (docs/publicacao-android-enterprise.md). Sem elas, o build de release para com o motivo.
    val chave = System.getenv("AURORA_ASSINATURA_ARQUIVO")
    signingConfigs {
        if (chave != null) {
            create("publicacao") {
                storeFile = file(chave)
                storePassword = System.getenv("AURORA_ASSINATURA_SENHA")
                keyAlias = System.getenv("AURORA_ASSINATURA_ALIAS")
                keyPassword = System.getenv("AURORA_ASSINATURA_SENHA_CHAVE") ?: System.getenv("AURORA_ASSINATURA_SENHA")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (chave != null) signingConfigs.getByName("publicacao") else null
        }
    }
}

// Release sem a chave não sai (um APK assinado com a chave de debug não pode ir para o MDM).
val pedeRelease = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (pedeRelease && System.getenv("AURORA_ASSINATURA_ARQUIVO") == null) {
    throw GradleException(
        "Defina AURORA_ASSINATURA_ARQUIVO, AURORA_ASSINATURA_SENHA e AURORA_ASSINATURA_ALIAS para gerar o release " +
            "(docs/publicacao-android-enterprise.md)."
    )
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
