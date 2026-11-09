import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Modo demo: Flutter pasa los --dart-define a Gradle (propiedad "dart-defines", base64 separados por
// coma). Solo con MODO_DEMO=true la APK recibe otro id y nombre, para convivir con la app real.
val modoDemo: Boolean =
    ((project.findProperty("dart-defines") as String?) ?: "")
        .split(",")
        .filter { it.isNotEmpty() }
        .map { String(Base64.getDecoder().decode(it)) }
        .contains("MODO_DEMO=true")

// Llave propia de la demo, FUERA del repo: VIASOFIA_DEMO_KEYSTORE_PROPS apunta a un .properties con
// storeFile, storePassword, keyAlias y keyPassword. Sin ella la compilación demo falla.
val demoKeystoreProps: Properties? =
    System.getenv("VIASOFIA_DEMO_KEYSTORE_PROPS")
        ?.let { file(it) }
        ?.takeIf { it.isFile }
        ?.let { f -> Properties().apply { f.inputStream().use { load(it) } } }

android {
    namespace = "com.geb.agentreservas_conductor"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        // flutter_local_notifications (alerta de ruta de la demo) lo exige.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.geb.agentreservas_conductor"
        minSdk = 24
        targetSdk = 34
        // Una sola fuente de verdad: la versión de pubspec.yaml (version: X.Y.Z+N).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue(
            "string",
            "app_name",
            if (modoDemo) "Viasofia Demo" else "AgentReservas Conductor",
        )
        if (modoDemo) applicationIdSuffix = ".demo"
    }

    signingConfigs {
        if (demoKeystoreProps != null) {
            create("demo") {
                storeFile = file(demoKeystoreProps.getProperty("storeFile"))
                storePassword = demoKeystoreProps.getProperty("storePassword")
                keyAlias = demoKeystoreProps.getProperty("keyAlias")
                keyPassword = demoKeystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (modoDemo) {
                    // La demo nunca se firma con la llave debug.
                    checkNotNull(demoKeystoreProps) { "Falta VIASOFIA_DEMO_KEYSTORE_PROPS" }
                    signingConfigs.getByName("demo")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
