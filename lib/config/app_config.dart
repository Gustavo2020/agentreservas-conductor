/// Configuración global de la app AgentReservas Conductor.
/// Cambiar [baseUrl] según el entorno.
class AppConfig {
  AppConfig._();

  // ── URLs ───────────────────────────────────────────────────────────────────
  // Emulador Android:   http://10.0.2.2:8001  (default)
  // Dispositivo físico: http://localhost:8001  (con adb reverse — ver dev-usb.sh)
  // Producción:         https://api.geb.com.co
  // Sobrescribir en tiempo de build: --dart-define=BASE_URL=http://localhost:8001
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://10.0.2.2:8001',
  );
  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://10.0.2.2:8001',
  );

  // ── Modo demo ──────────────────────────────────────────────────────────────
  /// APK de demostración comercial: se activa SOLO al compilar con
  /// `--dart-define=MODO_DEMO=true`. En la APK normal es siempre false.
  /// En demo no hay login con segundo factor (se enlaza con un código de 6
  /// dígitos) y el teléfono NO manda su GPS: la posición la genera el servidor.
  static const bool modoDemo = bool.fromEnvironment('MODO_DEMO');

  /// Longitud del código de enlace que muestra el panel durante la simulación.
  static const int codigoEnlaceLongitud = 6;

  /// Punto de partida (San Juan del Cesar) si aún no llegó ninguna posición del
  /// servidor y hay que reportar «en sitio»: aproximado, solo para la demo.
  static const double demoLatInicial = 10.7706;
  static const double demoLngInicial = -73.0033;

  // ── Timeouts ───────────────────────────────────────────────────────────────
  static const Duration httpTimeout = Duration(seconds: 30);
  static const Duration wsReconnectDelay = Duration(seconds: 3);
  static const int wsMaxReconnectAttempts = 10;

  // ── Sesión ─────────────────────────────────────────────────────────────────
  static const String jwtStorageKey = 'conductor_jwt';
  static const String userDataKey = 'conductor_user';

  /// Identificador del aparato enrolado en el servidor. Sobrevive al cierre de
  /// sesión: cerrar sesión no es perder el segundo factor.
  static const String dispositivoIdKey = 'conductor_dispositivo_id';

  // ── Segundo factor (llave del aparato) ─────────────────────────────────────
  /// Alias de la llave ECDSA P-256 en el Keystore. Una por instalación.
  static const String llaveAlias = 'agentreservas_conductor_llave';

  /// Prefijo que el servidor antepone al reto antes de verificar la firma.
  /// Debe coincidir con `DOMINIO_FIRMA` de parametrizacion.
  static const String dominioFirma = 'patrix:conductor:v1:';

  /// Nombre con el que el aparato se presenta al administrador.
  static const String nombreDispositivo = 'Teléfono Android del conductor';

  // ── GPS ────────────────────────────────────────────────────────────────────
  /// Intervalo de envío GPS durante modo pánico (1 segundo)
  static const Duration gpsPanicoInterval = Duration(seconds: 1);

  /// Timeout chequeo horario antes de reportar ANORMAL automáticamente
  static const Duration chequeoTimeout = Duration(minutes: 60);

  // ── Fotos ──────────────────────────────────────────────────────────────────
  static const int fotoMaxMB = 5;
}
