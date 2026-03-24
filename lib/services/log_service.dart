import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

// ── Salida a archivo ─────────────────────────────────────────────────────────

/// Escribe cada evento de log en un archivo rotativo por fecha.
/// El archivo se inicializa de forma diferida en la primera escritura.
///
/// Ruta: `<AppDocuments>/logs/app_YYYY-MM-DD.log`
class _FileOutput extends LogOutput {
  File? _file;
  bool _initialized = false;

  static String get _dateTag {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Ruta del archivo activo, o null si todavía no se inicializó.
  static String? _filePath;

  static String? get currentFilePath => _filePath;

  /// Resuelve la ruta y crea el directorio/archivo si no existen.
  Future<File?> _getFile() async {
    if (_initialized) return _file;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!logDir.existsSync()) logDir.createSync(recursive: true);
      _filePath = '${logDir.path}/app_$_dateTag.log';
      _file = File(_filePath!);
      _initialized = true;
    } catch (_) {
      // Si falla la resolución de ruta (ej. tests), no romper la app.
      _initialized = true; // evitar reintentos infinitos
    }
    return _file;
  }

  @override
  void output(OutputEvent event) {
    // Escritura asíncrona: no bloqueamos el hilo principal.
    _getFile().then((f) {
      if (f == null) return;
      final lines = event.lines.join('\n');
      f.writeAsStringSync('$lines\n', mode: FileMode.append, flush: true);
    });
  }
}

// ── Salida a Crashlytics / Sentry (stub producción) ─────────────────────────

/// Stub listo para integrar Sentry.captureException / FirebaseCrashlytics.
/// En release imprime en consola hasta que el SDK de crash reporting esté
/// configurado.
class _CrashOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    // TODO: integrar Sentry.captureException / FirebaseCrashlytics.recordError
    for (final line in event.lines) {
      // ignore: avoid_print
      print(line);
    }
  }
}

// ── AppLogger ────────────────────────────────────────────────────────────────

/// Servicio centralizado de logging para la app.
///
/// **Inicialización obligatoria en `main()`:**
/// ```dart
/// await AppLogger.init();
/// ```
///
/// **Uso:**
/// ```dart
/// AppLogger.info('Login exitoso', context: {'conductor_id': '42'});
/// AppLogger.error('Error de red', e, stackTrace: st,
///     context: {'path': '/api/...', 'status': '500'});
/// AppLogger.fatal('WS sin reconexión', e, context: {'solicitud_id': '7'});
/// ```
///
/// **Privacidad:**
/// - JWTs redactados automáticamente (`<JWT_REDACTED>`).
/// - Campos `"password"` redactados automáticamente.
/// - Nunca pasar tokens, cédulas ni nombres completos en `context`.
///
/// **Archivo de log (debug):** `<AppDocuments>/logs/app_YYYY-MM-DD.log`
class AppLogger {
  AppLogger._();

  static final _fileOutput = _FileOutput();

  /// Ruta del archivo de log activo. Disponible tras `init()`.
  static String? get logFilePath => _FileOutput.currentFilePath;

  static Logger? _debugLogger;
  static Logger? _releaseLogger;

  /// Debe llamarse una vez en `main()` antes de `runApp()`.
  /// Fuerza la inicialización del archivo de log para que `logFilePath`
  /// esté disponible desde el primer frame.
  static Future<void> init() async {
    // Fuerza la creación del archivo antes de que llegue el primer log.
    await _fileOutput._getFile();
    _debugLogger = Logger(
      printer: PrettyPrinter(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 100,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
      output: MultiOutput([ConsoleOutput(), _fileOutput]),
      level: Level.trace,
    );
    _releaseLogger = Logger(
      printer: SimplePrinter(printTime: true, colors: false),
      output: MultiOutput([_CrashOutput(), _fileOutput]),
      level: Level.warning,
    );
  }

  static Logger get _logger {
    // Fallback en caso de que init() no haya sido llamado todavía.
    _debugLogger ??= Logger(
      printer: PrettyPrinter(methodCount: 2, errorMethodCount: 8),
      output: MultiOutput([ConsoleOutput(), _fileOutput]),
      level: Level.trace,
    );
    _releaseLogger ??= Logger(
      printer: SimplePrinter(printTime: true, colors: false),
      output: MultiOutput([_CrashOutput(), _fileOutput]),
      level: Level.warning,
    );
    return kDebugMode ? _debugLogger! : _releaseLogger!;
  }

  // ── Sanitización PII ───────────────────────────────────────────────────────

  static final _jwtRegex = RegExp(
    r'eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]*',
  );

  static String _sanitize(String input) => input
      .replaceAll(_jwtRegex, '<JWT_REDACTED>')
      .replaceAll(
        RegExp(r'"password"\s*:\s*"[^"]*"'),
        '"password":"<REDACTED>"',
      );

  static String _fmt(String message, Map<String, dynamic>? context) {
    final base = _sanitize(message);
    if (context == null || context.isEmpty) return base;
    final sanitizedCtx =
        context.map((k, v) => MapEntry(k, _sanitize(v.toString())));
    return '$base | ctx=$sanitizedCtx';
  }

  // ── API pública ────────────────────────────────────────────────────────────

  /// Evento informativo (flujo normal: login, conexión WS, inicio de viaje).
  static void info(String message, {Map<String, dynamic>? context}) =>
      _logger.i(_fmt(message, context));

  /// Situación inesperada pero recuperable (credenciales inválidas, reconexión WS).
  static void warning(String message, {Map<String, dynamic>? context}) =>
      _logger.w(_fmt(message, context));

  /// Error de red, GPS o cámara que no interrumpe la sesión.
  ///
  /// Según GUIDELINES §7.6: toda llamada a `error()` debe ir acompañada de
  /// feedback visual al usuario (SnackBar con `AppTheme.error`).
  static void error(
    String message,
    Object error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) =>
      _logger.e(_fmt(message, context), error: error, stackTrace: stackTrace);

  /// Error crítico: sesión comprometida o flujo completamente roto.
  static void fatal(
    String message,
    Object error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) =>
      _logger.f(_fmt(message, context), error: error, stackTrace: stackTrace);
}
