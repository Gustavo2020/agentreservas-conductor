# GUIDELINES — AgentReservas Conductor

> **Este documento es de consulta obligatoria antes de iniciar cualquier tarea de desarrollo.**
> Toda implementación que no cumpla estas reglas será rechazada en revisión de código.

---

## 1. Arquitectura de Software

### 1.1 Gestión de Estado — Provider (obligatorio)

El único mecanismo de gestión de estado autorizado es **`provider ^6.1.0`**.
Queda prohibido el uso de `setState` fuera de widgets estrictamente locales (ej. animaciones, formularios sin lógica de negocio).

**Reglas de uso:**
- Los providers se registran en `main.dart` mediante `MultiProvider`.
- Los widgets leen estado con `context.watch<T>()` (rebuild reactivo) o `context.read<T>()` (acción puntual, sin rebuild).
- Nunca llamar `context.read<T>()` dentro de `build()`.
- Toda lógica de negocio vive en el Provider o en el Service correspondiente; las pantallas sólo disparan acciones y renderizan estado.

```
// CORRECTO
onPressed: () => context.read<ViajeProvider>().iniciarViaje(id),

// INCORRECTO
onPressed: () {
  setState(() { /* lógica de negocio aquí */ });
}
```

### 1.2 Estructura de Carpetas

```
lib/
├── config/
│   ├── app_config.dart      # URLs, timeouts, claves de storage, intervalos GPS
│   └── theme.dart           # Paleta de colores y ThemeData GEB
├── models/                  # Clases de datos inmutables + fromJson()
├── services/                # Comunicación externa (HTTP, WS, almacenamiento)
│   ├── api_service.dart     # Cliente HTTP con interceptor JWT
│   ├── auth_service.dart    # Login, logout, lectura de token/userData
│   └── ws_service.dart      # WebSocket — conexión, stream, sendGps()
├── providers/               # ChangeNotifier con estado derivado + acciones
│   ├── auth_provider.dart
│   ├── viaje_provider.dart
│   └── ws_provider.dart
├── screens/                 # Pantallas (una por feature)
└── widgets/                 # Componentes reutilizables
```

**Regla de dependencias (una sola dirección):**
```
screens/widgets  →  providers  →  services  →  models
```
- Un `screen` puede depender de uno o más `providers` y de servicios para navegación.
- Un `provider` nunca importa otro `provider` directamente; coordina a través del `screen` o de un `service` compartido.
- Un `service` nunca importa un `provider`.

### 1.3 Modelos

- Los modelos son **inmutables** (todos los campos `final`).
- Obligatorio implementar `factory NombreModelo.fromJson(Map<String, dynamic> json)`.
- No incluir lógica de negocio en los modelos; sólo parsing y getters derivados simples.

---

## 2. Seguridad de Identidad

### 2.1 Almacenamiento del JWT

El token JWT **sólo** puede almacenarse en `flutter_secure_storage`.
Está prohibido usar `SharedPreferences`, variables globales o cualquier otro mecanismo.

```dart
// Clave canónica definida en AppConfig
static const String jwtStorageKey = 'conductor_jwt';  // AppConfig.jwtStorageKey
static const String userDataKey   = 'conductor_user'; // AppConfig.userDataKey
```

Toda lectura y escritura del token pasa exclusivamente por `AuthService` (`getToken()`, `saveToken()`, `logout()`).
Ningún widget ni provider debe acceder a `FlutterSecureStorage` directamente.

### 2.2 Interceptor HTTP — Inyección Automática del Header Authorization

Toda llamada HTTP **debe** pasar por `ApiService`.
Queda prohibido construir instancias de `http.Client` o `http.Request` directamente en un provider o screen.

`ApiService` inyecta el header de forma transparente mediante `_headers()`:

```dart
Future<Map<String, String>> _headers() async {
  final token = await _auth.getToken();
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}
```

**Manejo de respuestas de autorización:**
- `401` o `403` → lanzar `ApiException` y redirigir al login desde el `AuthProvider`.
- `≥ 400` → lanzar `ApiException` con el mensaje `detail` del cuerpo JSON.
- El caller (provider) captura `ApiException` y expone el mensaje al usuario vía SnackBar.

### 2.3 WebSocket — Autenticación

La conexión WebSocket incluye el JWT como query param `?token=<jwt>` (ver `WsService`).
El token se obtiene de `AuthService.getToken()` inmediatamente antes de conectar; nunca se cachea en memoria fuera de `AuthService`.

---

## 3. Captura de Evidencia Inmutable

### 3.1 Prohibición de Galería

```dart
// PROHIBIDO en cualquier parte del código
ImagePicker().pickImage(source: ImageSource.gallery)

// OBLIGATORIO — únicamente fuente cámara
ImagePicker().pickImage(source: ImageSource.camera, ...)
```

La captura de imágenes para checklist y soportes se implementa exclusivamente a través del widget `FotoGeolocalizadaWidget` (`lib/widgets/foto_geolocalizada.dart`).
No se crea ningún flujo alternativo de captura de imagen.

### 3.2 GPS + Timestamp Obligatorios en Cada Foto

Toda imagen enviada al servidor debe incluir:

| Campo       | Origen                               | Tipo     |
|-------------|--------------------------------------|----------|
| `lat`       | `Geolocator.getCurrentPosition()`    | `double` |
| `lng`       | `Geolocator.getCurrentPosition()`    | `double` |
| `timestamp` | `DateTime.now().toIso8601String()`   | `String` |

El GPS se obtiene **antes** de abrir la cámara para garantizar que las coordenadas corresponden al instante de la toma.
Si el GPS no está disponible o el permiso es denegado, la captura se cancela con mensaje de error; nunca se envía una foto sin coordenadas.

El resultado se encapsula en `FotoGeoResult`:
```dart
class FotoGeoResult {
  final Uint8List bytes;
  final String filename;   // '{campo}_{millisecondsSinceEpoch}.jpg'
  final double lat;
  final double lng;
  // El timestamp se construye del filename o se adjunta en el multipart
}
```

### 3.3 Límite de Tamaño

- Máximo: `AppConfig.fotoMaxMB` (5 MB).
- Compresión: `imageQuality: 85`, `maxWidth: 1920`, `maxHeight: 1080`.
- Formato de envío: `multipart/form-data` mediante `ApiService`.

---

## 4. Gestión de Operación Crítica

### 4.1 WebSockets — WsManager

La gestión del ciclo de vida WebSocket es responsabilidad de `WsService` + `WsProvider`.

**Reconexión automática:**

| Parámetro                          | Valor (`AppConfig`)          |
|------------------------------------|------------------------------|
| Delay entre intentos               | `wsReconnectDelay` (3 s)     |
| Máximo de intentos                 | `wsMaxReconnectAttempts` (10)|

- Al superar el máximo de intentos, `WsProvider` notifica al usuario con un SnackBar de error persistente.
- La reconexión es exponencial a partir del tercer intento (3 s, 6 s, 9 s, máx. 30 s).
- El listener `WsProvider._onWsChange()` es el único punto de entrada de eventos WS hacia la UI; nunca escuchar el stream de `WsService` directamente desde un widget.

**Tipos de mensaje manejados (enum `WsMensajeTipo`):**

```
chequeoRequest      → mostrar BottomSheet de chequeo
viajeConfirmado     → activar flag viajeConfirmadoPorSolicitante → ViajeActivoScreen
                      llama iniciarViaje() automáticamente → estado enRuta
                      (no requiere acción adicional del conductor)
solicitudCancelada  → alerta con navegación a lista de viajes
aprobacionChecklist → recargar detalle del viaje
aprobacionSoporte   → recargar soportes del día
notificacion        → mostrar SnackBar informativo
```

**Flujo completo de abordaje:**
1. Conductor presiona "Estoy en el sitio de recogida" → API `en-sitio` → bot+email al solicitante
2. App muestra spinner "Esperando confirmación..." (estado `esperandoConfirmacionUsuario`)
3. Solicitante confirma en bot/email → API `confirmar-abordaje` → WS `VIAJE_CONFIRMADO`
4. App recibe WS → llama `iniciarViaje()` automáticamente → API `iniciar-viaje` → `EN_CURSO` en BD
5. Estado final: `enRuta` — sin intervención adicional del conductor

**Modo Pánico (`EstadoViajeActivo.modoPanico`):**

- Activado por: respuesta ANORMAL en chequeo horario o acción explícita del conductor.
- Comportamiento: transmisión GPS cada `AppConfig.gpsPanicoInterval` (1 segundo) vía `WsProvider.sendGps()`.
- El timer GPS se inicia en `_iniciarGpsParanico()` y se detiene en `_detenerGpsPanico()`.
- El modo pánico persiste hasta que el conductor presiona "Situación normalizada" → `WsProvider.desactivarModoPanico()`.
- **Nunca** detener el timer GPS desde fuera de `ViajeActivoScreen`; el ciclo de vida está ligado al `dispose()` de la pantalla.

**Chequeo Horario:**

- Timeout automático: `AppConfig.chequeoTimeout` (60 minutos). Si el conductor no responde, se reporta ANORMAL automáticamente.
- El BottomSheet de chequeo es `isDismissible: false` y `enableDrag: false`.

### 4.2 Validación de Soportes

**Teclado numérico obligatorio** en todos los campos de monto:

```dart
TextFormField(
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
  ...
)
```

**Bloqueo de cierre de día con soportes pendientes:**

- Antes de permitir "Cerrar día", verificar que todos los soportes del día tengan estado `APROBADO` o `RECHAZADO`.
- Si existen soportes en estado `PENDIENTE`, mostrar SnackBar de error y bloquear la acción.
- La validación ocurre en `ViajeProvider` antes de llamar al endpoint.

**Bloqueo de reporte en sitio sin checklist aprobado:**

- El botón "Estoy en el sitio de recogida" verifica `viaje.checklist?.aprobado == true`.
- Si el checklist no fue aprobado por el responsable, mostrar SnackBar con instrucción y retornar sin llamar a la API.

---

## 5. Estándares de UI/UX

### 5.1 Paleta de Colores Corporativa GEB

Toda referencia de color usa **exclusivamente** las constantes de `AppTheme` (`lib/config/theme.dart`).
Está prohibido usar `Colors.*` de Material salvo en componentes de sistema (ej. `Colors.black54` para overlays).

| Constante              | Hex         | Uso                                      |
|------------------------|-------------|------------------------------------------|
| `AppTheme.primary`     | `#E8A020`   | Botones primarios, iconos de acción      |
| `AppTheme.success`     | `#10B981`   | Estados positivos, confirmaciones        |
| `AppTheme.error`       | `#EF4444`   | Errores, alertas críticas, modo pánico   |
| `AppTheme.warning`     | `#F59E0B`   | Estados intermedios, advertencias        |
| `AppTheme.background`  | `#1A1E25`   | Fondo de pantallas (`Scaffold`)          |
| `AppTheme.surface`     | `#252A33`   | Tarjetas, BottomSheets, inputs           |
| `AppTheme.onBackground`| `#E5E7EB`   | Texto principal                          |
| `AppTheme.onSurface`   | `#CBD5E1`   | Texto secundario, labels                 |
| `AppTheme.divider`     | `#374151`   | Separadores, bordes                      |

### 5.2 Estados de Carga

**Toda operación asíncrona** que modifique datos visibles al usuario debe:

1. Activar un indicador de carga **antes** de iniciar la operación.
2. Desactivarlo en el bloque `finally`.
3. Usar `LoadingOverlay` para operaciones de pantalla completa o `CircularProgressIndicator` inline para botones.

```dart
// Patrón obligatorio en providers
Future<bool> accionCritica(int id) async {
  _loading = true;
  notifyListeners();
  try {
    final result = await _api.post(...);
    return result;
  } on ApiException catch (e) {
    _error = e.message;
    return false;
  } finally {
    _loading = false;
    notifyListeners();
  }
}
```

```dart
// Patrón obligatorio en screens con acción local
setState(() => _procesando = true);
try {
  await context.read<MiProvider>().accion();
} finally {
  if (mounted) setState(() => _procesando = false);
}
```

### 5.3 Navegación

- Usar `Navigator.of(context).push(MaterialPageRoute(...))` para navegación estándar.
- Para volver a la raíz: `Navigator.of(context).popUntil((r) => r.isFirst)`.
- No usar `Navigator.pushReplacementNamed` ni rutas con nombre; la app usa rutas imperativas.
- Verificar `if (!mounted) return;` antes de cualquier operación de contexto tras un `await`.

### 5.4 Accesibilidad y Responsividad

- Todos los botones de acción principal tienen `width: double.infinity` dentro de su contenedor.
- Padding mínimo de pantalla: `EdgeInsets.all(24)`.
- Tamaño mínimo de área táctil: 48×48 px (cumplido por `ElevatedButton` con el padding del tema).

---

## 6. Calidad de Código

### 6.1 Linter — analysis_options.yaml (estricto desde 2026-03-28)

Se usa un `analysis_options.yaml` con reglas adicionales a `flutter_lints`:
`prefer_const_constructors`, `avoid_dynamic_calls`, `unawaited_futures`,
`curly_braces_in_flow_control_structures`, `directives_ordering`, etc.
Ningún PR puede introducir issues sin justificación documentada.

```bash
flutter analyze          # debe terminar en "No issues found!"
dart format --set-exit-if-changed lib/ test/   # 0 cambios pendientes
flutter test --no-pub    # debe terminar en "All tests passed!"
```

**Orden correcto para fix de lint masivo (Dart):**
1. `dart format lib/ test/` — auto-fix ~80% de style issues
2. `flutter analyze` — identificar errores restantes por categoría
3. Fijar deprecated_member_use (withOpacity→withValues, CardTheme→CardThemeData)
4. Fijar avoid_dynamic_calls (tipar `dynamic` con la clase correcta)
5. Fijar unawaited_futures (envolver en `unawaited()` de `dart:async`)
6. Fijar directives_ordering (ordenar imports: dart: > package: > relative, alfa)
7. Fijar curly_braces (añadir `{}` a todos los if de 1 línea)
8. Re-correr `dart format` + `flutter analyze` — debe ser "No issues found!"

### 6.2 Manejo de Excepciones

**Regla universal:** todo bloque `async` que llama a la red, GPS o cámara usa `try-catch` con feedback visual obligatorio.

```dart
// CORRECTO
try {
  await context.read<ViajeProvider>().reportarEnSitio(...);
} catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se pudo completar la acción: $e'),
        backgroundColor: AppTheme.error,
      ),
    );
  }
}

// INCORRECTO — excepción silenciosa
try {
  await accion();
} catch (_) {}
```

**Jerarquía de excepciones:**
- `ApiException` → capturar en el provider, exponer `_error` como String.
- `Exception` / `Error` genérico → capturar en el screen, mostrar SnackBar con `AppTheme.error`.
- Errores de GPS → capturar en el screen o en `FotoGeolocalizadaWidget`, mostrar mensaje descriptivo.

### 6.3 Feedback Visual por Tipo de Resultado

| Situación                    | Color de SnackBar        | Duración sugerida |
|------------------------------|--------------------------|-------------------|
| Éxito                        | `AppTheme.success`       | 2 segundos        |
| Error de negocio (API 4xx)   | `AppTheme.error`         | 4 segundos        |
| Error técnico / red          | `AppTheme.error`         | 4 segundos        |
| Advertencia / validación     | `AppTheme.warning`       | 3 segundos        |
| Información                  | `AppTheme.surface`       | 2 segundos        |

### 6.4 Nomenclatura

| Elemento                | Convención         | Ejemplo                        |
|-------------------------|--------------------|--------------------------------|
| Clases                  | `UpperCamelCase`   | `ViajeProvider`, `AuthService` |
| Variables / métodos     | `lowerCamelCase`   | `_procesando`, `_tomarFoto()`  |
| Constantes              | `lowerCamelCase`   | `AppConfig.jwtStorageKey`      |
| Archivos                | `snake_case.dart`  | `viaje_activo_screen.dart`     |
| Widgets privados        | Prefijo `_`        | `_PanelEnRuta`, `_ChequeoBottomSheet` |

### 6.5 Cobertura de Tests

- Cobertura mínima aceptable: **80%** de líneas de lógica de negocio (providers y services).
- Los models deben tener tests de `fromJson` que cubran campos presentes, ausentes y con valores nulos.
- Los widgets críticos (`FotoGeolocalizadaWidget`, `EstadoBadge`, `LoadingOverlay`) requieren widget tests.
- Mocks HTTP: usar `MockClient` de `package:http/testing.dart`; el handler siempre es `Future<http.Response> Function(http.Request)`.
- `FlutterSecureStorage` en tests: inicializar con `FlutterSecureStorage.setMockInitialValues({})` en `setUp`.

---

## 7. Estrategia de Logging y Gestión de Errores

### 7.1 Captura Universal

Todo `catch` en un Service o Provider **debe** loguear el error.
Está prohibido silenciar excepciones sin registro (`catch (_) {}`).

```dart
// INCORRECTO
try { ... } on Exception catch (_) {}

// CORRECTO
try { ... } on Exception catch (e, st) {
  AppLogger.error('Descripción del fallo', e, stackTrace: st,
      context: {'solicitud_id': '$id'});
  rethrow; // o return fallback
}
```

### 7.2 Implementación del Logger — `AppLogger`

El único punto de entrada para registrar eventos es **`AppLogger`** (`lib/services/log_service.dart`).

| Método                                | Cuándo usarlo                                              |
|---------------------------------------|------------------------------------------------------------|
| `AppLogger.info(msg, {context})`      | Flujo normal: login, conexión WS, inicio de viaje          |
| `AppLogger.warning(msg, {context})`   | Situación inesperada pero recuperable: credenciales malas, reconexión |
| `AppLogger.error(msg, e, {st, ctx})`  | Error que no interrumpe la sesión: timeout HTTP, fallo de parse |
| `AppLogger.fatal(msg, e, {st, ctx})`  | Error crítico: WS sin reconexión, fallo de autenticación irrecuperable |

**Modo debug** (`kDebugMode = true`): `PrettyPrinter` con colores y emojis en consola.
**Modo release**: `SimplePrinter` + `_CrashOutput` (stub listo para Sentry / Crashlytics).

### 7.3 Contexto del Error

Cada llamada a `AppLogger` debe incluir el contexto mínimo necesario para reproducir el fallo:

```dart
AppLogger.error(
  'ApiService: error HTTP',
  exception,
  stackTrace: stackTrace,
  context: {
    'solicitud_id': '$solicitudId',  // ID de la solicitud afectada
    'conductor_id': '$conductorId',  // opcional
    'path': '/api/conductor/viajes/$id/chequeo',
    'status': '${response.statusCode}',
  },
);
```

Campos recomendados: `solicitud_id`, `conductor_id`, `path`, `status`, `intento`.

### 7.4 Privacidad — PII y Secretos

`AppLogger._sanitize()` redacta automáticamente:
- **JWTs** completos (patrón `eyJ…`).
- Campos `"password": "…"` en strings JSON.

Reglas adicionales que el desarrollador debe cumplir:
- Nunca pasar el token crudo como valor en el `context` map.
- Nunca loguear campos de formulario de usuario (nombre, cédula, número de placa) a nivel `info` o superior en producción.

### 7.5 Flujo de Depuración

En una sesión de desarrollo, el nivel mínimo de log es `Level.trace` (debug).
Para reducir ruido, filtrar por tag en Logcat:

```
adb logcat -s flutter
```

En release, sólo se emiten `warning`, `error` y `fatal`.

### 7.6 Feedback Visual al Usuario

El logging **no reemplaza** el feedback visual. Son responsabilidades separadas:

| Capa        | Responsabilidad                                              |
|-------------|--------------------------------------------------------------|
| `AppLogger` | Registro técnico para el equipo de desarrollo / Crashlytics  |
| SnackBar    | Mensaje amigable al usuario (`AppTheme.error`, 4 segundos)   |
| Dialog      | Confirmaciones destructivas o errores críticos de sesión     |

Regla: si se llama `AppLogger.error(...)`, el Provider o widget **también** debe mostrar un SnackBar con mensaje legible para el usuario.

---

## 8. Configuración de Entornos

Toda URL y configuración de entorno vive en `AppConfig` (`lib/config/app_config.dart`).
Está prohibido hardcodear URLs, claves o timeouts fuera de `AppConfig`.

| Entorno       | `baseUrl`                     | `wsBaseUrl`                  |
|---------------|-------------------------------|------------------------------|
| Emulador Android | `http://10.0.2.2:8001`    | `ws://10.0.2.2:8001`         |
| Dispositivo físico | IP local de la máquina  | IP local de la máquina       |
| Producción    | `https://api.geb.com.co`      | `wss://api.geb.com.co`       |

Para cambiar de entorno, modificar `AppConfig.baseUrl` y `AppConfig.wsBaseUrl`. En un futuro se migrará a variables de entorno mediante `--dart-define`.

---

## 9. Lecciones Aprendidas

### L1 — Import regex en scripts de sorting debe manejar `as alias`

**Caso:** Un script Python que ordenaba imports de Dart con regex `import\s+'[^']+';` eliminó silenciosamente `import 'package:http/http.dart' as http;` porque el patrón no incluía `as alias` después de la comilla de cierre.

**Regla:** El patrón correcto es:
```python
re.compile(r"""^\s*import\s+'[^']+'\s*(?:\s+(?:as|show|hide)\s+[\w\s,]+)?;""")
```
Verificar siempre que los imports con alias (`as http`, `show X`, `hide Y`) son preservados.

### L2 — `unawaited()` requiere `dart:async` import explícito

**Caso:** Envolver Navigator calls en `unawaited()` sin añadir `import 'dart:async'` genera "method not defined".

**Regla:** Siempre añadir `import 'dart:async';` al usar `unawaited()`. La línea debe ir en el grupo `dart:` (antes de los `package:`).

### L3 — Compatibilidad Flutter: `CardTheme` vs `CardThemeData`, `withOpacity` vs `withValues`

**Caso:** El patch de compatibilidad cambió `CardThemeData` → `CardTheme` y `withValues` → `withOpacity`. Con Flutter >=3.27 se debe usar `CardThemeData` y `withValues(alpha:)` (el modo retrocompatible genera deprecated warnings).

**Regla:** Actualizar `pubspec.yaml` `flutter: ">=X.Y"` al nivel de APIs usadas. Si el mínimo es >=3.27, usar `CardThemeData` y `.withValues(alpha:)`.

### L4 — `git stash` en proyectos con WIP stash de sesión anterior

**Caso:** El conductor tenía un stash de sesión anterior con trabajo incompleto. Al hacer `git stash pop` se restauró ese trabajo roto (24 errores).

**Regla:** Verificar `git stash list` antes de cualquier `git stash pop`. Si el stash tiene trabajo de sesión anterior desconocido, inspeccionarlo con `git stash show -p stash@{0}` antes de aplicarlo.

---

## 10. Checklist Pre-commit

Antes de abrir un PR, verificar:

- [ ] `flutter analyze` sin warnings
- [ ] `flutter test --no-pub` con todos los tests en verde
- [ ] Ningún `ImageSource.gallery` en el código
- [ ] Ningún acceso directo a `FlutterSecureStorage` fuera de `AuthService`
- [ ] Ningún `http.Client()` instanciado fuera de `ApiService`
- [ ] Toda operación async tiene `try-catch` con feedback visual
- [ ] Todos los campos de monto usan `TextInputType.numberWithOptions`
- [ ] Verificación `if (!mounted) return;` tras cada `await` en un `State`
- [ ] Colores referenciados desde `AppTheme`, no desde `Colors.*`
- [ ] Nuevas pantallas registradas correctamente con sus providers en `main.dart`
- [ ] Ningún `catch` silencioso — todo error registrado con `AppLogger`
- [ ] Ningún JWT ni `password` pasado directamente a `AppLogger` sin sanitizar
- [ ] Cada `AppLogger.error(...)` acompañado de feedback visual al usuario


### L5 — El segundo factor se prueba en dos mitades
La lógica (qué se firma, qué se guarda, qué mensaje ve la persona) se prueba con
una llave y un servidor simulados; lo que depende del hardware (huella, PIN,
Keystore) solo se comprueba en un teléfono real. Mantener la llave detrás de una
interfaz (`FirmaDispositivo`) permite lo primero sin enmascarar lo segundo.
Antes de dar por terminada una función con biometría, hacer la prueba manual y
anotarla en el README.

### L6 — Un `dart format` sobre toda la carpeta toca archivos ajenos
Formatear `lib/` completo reformatea también el trabajo sin commitear de otra
persona. Formatear solo los archivos propios (`dart format <archivo>`).
