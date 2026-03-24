# AgentReservas Conductor

App móvil para conductores del sistema AgentReservas — GEB.

## Requisitos

| Herramienta | Versión mínima |
|-------------|---------------|
| Flutter     | 3.19.0        |
| Dart        | 3.0.0         |
| Android SDK | 34            |
| Java        | 17            |
| Android     | 7.0+ (API 24) |

## Setup

```bash
# 1. Clonar/ubicar el proyecto
cd ~/Proyects/agentreservas-conductor

# 2. Instalar dependencias
flutter pub get

# 3. Conectar dispositivo Android o iniciar emulador

# 4. Ejecutar en modo desarrollo
flutter run
```

## Configuración del backend

Editar `lib/config/app_config.dart`:

```dart
static const String baseUrl   = 'http://192.168.X.X:8001';  // IP del servidor en la red
static const String wsBaseUrl = 'ws://192.168.X.X:8001';
```

Para producción usar HTTPS/WSS:

```dart
static const String baseUrl   = 'https://tu-dominio.com';
static const String wsBaseUrl = 'wss://tu-dominio.com';
```

## Build APK para distribución

```bash
# APK de release (obfuscado)
flutter build apk --release

# Ubicación del APK:
# build/app/outputs/flutter-apk/app-release.apk
```

Copiar el APK a los dispositivos de los conductores vía:
- ADB: `adb install build/app/outputs/flutter-apk/app-release.apk`
- Transferencia directa por WhatsApp/email (habilitar "Fuentes desconocidas" en el dispositivo)

## Arquitectura

```
lib/
├── config/         # URLs, tema GEB (fondo #1a1e25, accent #e8a020)
├── models/         # Viaje, Trayecto, Checklist, Soporte
├── services/
│   ├── auth_service.dart   # Login + JWT en Android Keystore
│   ├── api_service.dart    # HTTP client con interceptor JWT
│   └── ws_service.dart     # WebSocket + reconexión automática
├── providers/      # Estado con Provider (Auth, Viaje, Ws)
├── screens/        # 7 pantallas principales
└── widgets/        # FotoGeolocalizada, EstadoBadge, LoadingOverlay
```

## Flujo del conductor

1. **Login** — POST /api/auth/conductor-login (JWT 12h, sin 2FA)
2. **Mis viajes** — Ver viajes APROBADO / EN_CURSO
3. **Detalle** — Tabs: Ruta · Checklist · Estado
4. **Checklist** — 5 fotos geolocalización obligatoria → enviar a revisión
5. **Viaje activo** — En sitio → confirmar abordaje → iniciar viaje → chequeos horarios
6. **Soportes** — PEAJE / PARQUEADERO / LAVADO con foto y monto
7. **Cierre de día** — Resumen + enviar a revisión del solicitante
8. **Cierre de viaje** — Cuando todos los soportes están aprobados

## Seguridad

- JWT almacenado en **Android Keystore** vía `flutter_secure_storage`
- Fotos capturadas **solo con cámara** (galería deshabilitada)
- Fotos NO se guardan en el dispositivo — se envían directamente al servidor
- GPS obligatorio para todas las fotos del checklist
- Modo pánico: GPS enviado cada segundo vía WebSocket al equipo de Seguridad Física
- Certificate pinning recomendado para producción (configurar en `api_service.dart`)
