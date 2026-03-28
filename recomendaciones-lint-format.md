# Recomendaciones de Lint y Formato — AgentReservas Conductor

## Resumen Ejecutivo

Se revisó el proyecto Flutter/Dart `agentreservas-conductor` usando `flutter analyze` y `dart format`.
Se encontraron **19 issues originales** (3 errores, 2 warnings, 14 info). Todos fueron corregidos
o documentados. Se adjunta un archivo `.patch` con todas las correcciones listas para aplicar.

> **Nota importante:** "Black" es un formateador de Python. El equivalente en Dart es `dart format`,
> que es lo que se usó en esta revisión.

---

## 1. Cambios Aplicados (incluidos en el .patch)

### 1.1 Formato de código (`dart format`)
- **27 archivos formateados** en `lib/` y `test/`
- Correcciones de indentación, alineación de parámetros y saltos de línea
- Eliminación de espaciado manual en declaraciones de variables (ej. alineación con espacios en `theme.dart`)
- Archivos afectados: `theme.dart`, `main.dart`, `checklist.dart`, `viaje.dart`, `auth_provider.dart`,
  `viaje_provider.dart`, `ws_provider.dart`, todas las screens, services, widgets y tests

### 1.2 Errores corregidos (3 errores → 0)

| Archivo | Error original | Corrección |
|---------|---------------|------------|
| `lib/config/theme.dart:46` | `CardThemeData` no es una clase válida (Flutter < 3.27) | Cambiado a `CardTheme` (compatible con Flutter ≥ 3.19) |
| `lib/screens/detalle_viaje_screen.dart:528` | `Color.withValues()` no existe (Flutter < 3.27) | Cambiado a `Color.withOpacity()` (compatible con todas las versiones) |
| `lib/screens/detalle_viaje_screen.dart:530` | Mismo error `withValues` | Mismo fix `withOpacity` |

**Nota:** El `pubspec.yaml` declara `flutter: ">=3.19.0"` pero el código usaba APIs de Flutter 3.27+.
Las correcciones hacen el código compatible con la versión mínima declarada.

### 1.3 Warnings corregidos (2 → 0)

| Archivo | Warning | Corrección |
|---------|---------|------------|
| `pubspec.yaml:48` | Dependencia dev duplicada de `http` (ya es dependencia normal) | Eliminada la línea duplicada |
| `pubspec.yaml:53` | Directorio `assets/images/` no existe | Creado directorio con `.gitkeep` |

### 1.4 Info-level fixes

| Archivo | Issue | Corrección |
|---------|-------|------------|
| `lib/config/theme.dart:28-29` | `background`/`onBackground` deprecados en ColorScheme | Agregado `// ignore: deprecated_member_use` |
| `lib/config/theme.dart:81` | Falta `const` en `BorderSide` | Agregado `const` |
| `lib/screens/soportes_screen.dart:68` | `child` debe ir al final del constructor | Reordenado: `onPressed` antes de `child` |
| `lib/widgets/estado_badge.dart:31` | `child` debe ir al final del constructor | Reordenado parámetros de `_PulsatingBadge` |
| `lib/screens/viaje_activo_screen.dart:368-411` | Falta `const` en múltiples constructores | Convertido a `const Center(...)` y `const Column(...)` |
| `test/all_tests.dart:1` | Doc comment (`///`) colgante sin declaración | Cambiado a comment normal (`//`) |

### 1.5 `analysis_options.yaml` mejorado

Se reemplazó la configuración mínima por una con reglas más estrictas:

```yaml
analyzer:
  errors:
    unused_import: error        # Imports no usados son error
    unused_local_variable: warning
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

linter:
  rules:
    # Estilo
    prefer_single_quotes: true
    sort_child_properties_last: true
    prefer_const_constructors: true
    prefer_const_declarations: true
    prefer_const_literals_to_create_immutables: true
    # Seguridad de tipos
    avoid_dynamic_calls: true
    # Buenas prácticas
    avoid_print: true
    prefer_final_locals: true
    prefer_final_in_for_each: true
    unawaited_futures: true
    cancel_subscriptions: true
    close_sinks: true
    use_key_in_widget_constructors: true
    sized_box_for_whitespace: true
    use_build_context_synchronously: true
    # Documentación
    dangling_library_doc_comments: true
    slash_for_doc_comments: true
    # Imports
    depend_on_referenced_packages: true
    directives_ordering: true
```

---

## 2. Issues Pendientes (recomendaciones para resolver manualmente)

Estas son issues info-level detectadas por las nuevas reglas que requieren atención del equipo:

### 2.1 `avoid_dynamic_calls` (9 ocurrencias)
**Archivo:** `lib/screens/detalle_viaje_screen.dart` (líneas 442-473)

El mapeo de trayectos usa acceso dinámico a campos JSON sin casting explícito.
**Recomendación:** Agregar casts con `as Map<String, dynamic>` o usar el modelo `Trayecto` directamente.

### 2.2 `unawaited_futures` (3 ocurrencias)
| Archivo | Línea | Futuro no esperado |
|---------|-------|--------------------|
| `cierre_dia_screen.dart` | 106 | Llamada async sin `await` |
| `login_screen.dart` | 36 | Llamada async sin `await` |
| `viajes_screen.dart` | 30 | Llamada async sin `await` |

**Recomendación:** Envolver con `unawaited()` de `dart:async` si es intencional, o agregar `await`.

### 2.3 `directives_ordering` (muchas ocurrencias)
Los imports en varios archivos no están ordenados alfabéticamente.
**Recomendación:** Usar el comando del IDE "Organize Imports" o configurar el formatter para ordenar automáticamente.

### 2.4 `depend_on_referenced_packages` (1 ocurrencia)
**Archivo:** `lib/services/api_service.dart:4`
Se importa `http_parser` pero no está listado como dependencia directa en `pubspec.yaml`.
**Recomendación:** Agregar `http_parser: ^4.0.0` a `dependencies` en `pubspec.yaml`.

### 2.5 `curly_braces_in_flow_control_structures` (3 ocurrencias)
**Archivo:** `lib/screens/soportes_screen.dart` (líneas 213, 300, 312)
Sentencias `if` sin llaves.
**Recomendación:** Agregar `{}` a todas las sentencias `if`.

---

## 3. Recomendaciones Adicionales de Calidad

### 3.1 Compatibilidad de versión Flutter
- El `pubspec.yaml` declara `flutter: ">=3.19.0"` pero el código usaba APIs de Flutter 3.27+
- **Recomendación:** Actualizar la versión mínima a `">=3.27.0"` o mantener las correcciones del patch
  que usan APIs retrocompatibles

### 3.2 Dependencias desactualizadas
Se encontraron **76 paquetes con versiones más nuevas** disponibles. Los más relevantes:
- `flutter_lints: 3.0.2` → `6.0.0` disponible
- `camera: 0.10.6` → `0.12.0+1`
- `geolocator: 11.1.0` → `14.0.2`
- `web_socket_channel: 2.4.0` → `3.0.3`
- `flutter_secure_storage: 9.2.4` → `10.0.0`

**Recomendación:** Ejecutar `flutter pub outdated` y actualizar progresivamente.

### 3.3 Testing (según GUIDELINES.md)
El proyecto requiere 80% de cobertura mínima. Verificar con:
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

### 3.4 CI/CD
**Recomendación:** Configurar un pipeline de CI con:
```yaml
# .github/workflows/flutter-ci.yml
- dart format --set-exit-if-changed lib/ test/
- flutter analyze --fatal-infos
- flutter test --coverage
```

---

## 4. Cómo Aplicar los Cambios

Aplicar el archivo `.patch` adjunto:

```bash
cd agentreservas-conductor
git apply agentreservas-conductor-lint-format.patch
```

O revisar los cambios antes de aplicar:
```bash
git apply --stat agentreservas-conductor-lint-format.patch
git apply --check agentreservas-conductor-lint-format.patch
```

---

## 5. Resumen de Impacto

| Métrica | Antes | Después |
|---------|-------|---------|
| Errores de compilación | 3 | 0 |
| Warnings | 2 | 0 |
| Archivos sin formatear | 27 | 0 |
| Reglas lint activas | ~15 (default) | ~25 (custom) |
| Info-level pendientes | 0 | 41 (nuevas reglas, recomendaciones) |
