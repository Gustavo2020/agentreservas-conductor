import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/log_service.dart';

/// Tipos de mensaje recibidos desde el servidor.
enum WsMensajeTipo {
  chequeoRequest,
  viajeConfirmado,
  aprobacionChecklist,
  aprobacionSoporte,
  solicitudCancelada,
  viajeTerminado,
  notificacion,
  tramoProhibido,
  posicionVehiculo,
  desconocido,
}

class WsMensaje {
  final WsMensajeTipo tipo;
  final Map<String, dynamic> data;

  const WsMensaje(this.tipo, this.data);

  static WsMensaje fromJson(Map<String, dynamic> json) {
    final tipo = json['tipo'] as String? ?? '';
    final t = switch (tipo) {
      'CHEQUEO_REQUEST' => WsMensajeTipo.chequeoRequest,
      'VIAJE_CONFIRMADO' => WsMensajeTipo.viajeConfirmado,
      'APROBACION_CHECKLIST' => WsMensajeTipo.aprobacionChecklist,
      'APROBACION_SOPORTE' => WsMensajeTipo.aprobacionSoporte,
      'SOLICITUD_CANCELADA' => WsMensajeTipo.solicitudCancelada,
      'VIAJE_FINALIZADO' => WsMensajeTipo.viajeTerminado,
      'NOTIFICACION' => WsMensajeTipo.notificacion,
      'TRAMO_PROHIBIDO' => WsMensajeTipo.tramoProhibido,
      'POSICION_VEHICULO' || 'POSICION' => WsMensajeTipo.posicionVehiculo,
      _ => WsMensajeTipo.desconocido,
    };
    return WsMensaje(t, json);
  }
}

/// Gestiona la conexión WebSocket con reconexión automática + backoff.
///
/// Con [resiliente] (solo la APK de demostración) la conexión se comporta como la de una app de
/// mensajería: reintenta SIN límite con espera creciente (tope [esperaMaxima]), detecta un socket
/// muerto que ya no responde y puede reconectarse al instante ([reconectarAhora]) cuando vuelve la
/// red o la app regresa al primer plano. La app de operación no lo activa y sigue como antes.
class WsService {
  final AuthService _auth;
  final WebSocketChannel Function(Uri) _crearCanal;

  /// Reintentos sin límite, espera con tope y vigilancia del socket muerto (solo demo).
  final bool resiliente;

  /// Tras dos intentos fallidos seguidos se llama a esto para saber si la sesión sigue vigente:
  /// un servidor que rechaza el socket por sesión revocada es indistinguible de una caída de red.
  /// La demo lo conecta a una llamada autenticada; un 401 cierra la sesión.
  final Future<void> Function()? verificarSesion;

  /// Espera máxima entre reintentos en modo [resiliente].
  final Duration esperaMaxima;

  /// Si no llega nada (ni siquiera la respuesta al ping) en este tiempo, el socket se da por muerto.
  final Duration silencioMaximo;

  final DateTime Function() _ahora;

  WsService(
    this._auth, {
    WebSocketChannel Function(Uri)? crearCanal,
    this.resiliente = false,
    this.verificarSesion,
    this.esperaMaxima = const Duration(seconds: 30),
    this.silencioMaximo = const Duration(seconds: 90),
    DateTime Function()? ahora,
  })  : _crearCanal = crearCanal ?? WebSocketChannel.connect,
        _ahora = ahora ?? DateTime.now;

  WebSocketChannel? _channel;
  StreamController<WsMensaje>? _controller;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  int _reconnectAttempts = 0;
  bool _intentionalClose = false;
  int? _solicitudId;
  late DateTime _ultimaActividad = _ahora();

  Stream<WsMensaje> get stream => _controller?.stream ?? const Stream.empty();

  bool get isConnected => _channel != null;

  // ── Conectar ───────────────────────────────────────────────────────────────

  Future<void> connect(int solicitudId) async {
    _solicitudId = solicitudId;
    _intentionalClose = false;
    _controller ??= StreamController<WsMensaje>.broadcast();
    await _doConnect();
  }

  Future<void> _doConnect() async {
    final token = await _auth.getToken();
    if (token == null || _intentionalClose) return;

    final uri = Uri.parse(
      '${AppConfig.wsBaseUrl}/ws/conductor/$_solicitudId?token=$token',
    );

    AppLogger.info('WsService: conectando', context: {
      'solicitud_id': '$_solicitudId',
      'intento': '$_reconnectAttempts'
    });

    try {
      // Un canal anterior que siga abierto se cierra antes de abrir el nuevo.
      if (_channel != null) _cleanChannel();
      final canal = _crearCanal(uri);
      _channel = canal;
      _ultimaActividad = _ahora();
      // En modo resiliente el contador solo se reinicia cuando llega algo del servidor: abrir el
      // canal no prueba que la conexión sirva (el servidor puede rechazar el apretón de manos).
      if (!resiliente) _reconnectAttempts = 0;

      // Escuchar mensajes. Los avisos de un canal viejo (ya reemplazado) se ignoran: sin esto, el
      // cierre tardío de un canal descartado mataría al nuevo.
      canal.stream.listen(
        (raw) {
          if (canal == _channel) _onMessage(raw);
        },
        onError: (Object e) {
          if (canal == _channel) _onError(e);
        },
        onDone: () {
          if (canal == _channel) _onDone();
        },
      );

      // Ping cada 30s para mantener conexión viva
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (resiliente && _silencioExcedido()) {
          AppLogger.warning('WsService: socket sin respuesta, se reconecta',
              context: {'solicitud_id': '$_solicitudId'});
          _cleanChannel();
          _scheduleReconnect();
          return;
        }
        _send({'tipo': 'PING'});
      });
    } on Exception catch (e, st) {
      AppLogger.error('WsService: error al conectar', e,
          stackTrace: st, context: {'solicitud_id': '$_solicitudId'});
      _scheduleReconnect();
    }
  }

  bool _silencioExcedido() =>
      _ahora().difference(_ultimaActividad) > silencioMaximo;

  /// Reconecta ya, sin esperar el temporizador: la red volvió o la app regresó al primer plano.
  /// Si el canal sigue vivo (hubo actividad reciente) no hace nada.
  Future<void> reconectarAhora() async {
    if (_intentionalClose || _solicitudId == null) return;
    if (_channel != null && !_silencioExcedido()) return;
    AppLogger.info('WsService: reconexión inmediata',
        context: {'solicitud_id': '$_solicitudId'});
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _cleanChannel();
    await _doConnect();
  }

  void _onMessage(dynamic raw) {
    _ultimaActividad = _ahora();
    if (resiliente) _reconnectAttempts = 0;
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final msg = WsMensaje.fromJson(json);
      _controller?.add(msg);
    } on Exception catch (e) {
      AppLogger.warning('WsService: mensaje malformado ignorado',
          context: {'error': '$e'});
    }
  }

  void _onError(Object error) {
    AppLogger.error('WsService: error en stream', error,
        context: {'solicitud_id': '$_solicitudId'});
    _cleanChannel();
    _scheduleReconnect();
  }

  void _onDone() {
    if (!_intentionalClose) {
      AppLogger.warning('WsService: conexión cerrada inesperadamente',
          context: {'solicitud_id': '$_solicitudId'});
    }
    _cleanChannel();
    if (!_intentionalClose) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_intentionalClose) return;
    if (!resiliente && _reconnectAttempts >= AppConfig.wsMaxReconnectAttempts) {
      AppLogger.fatal(
        'WsService: máximo de reconexiones alcanzado',
        Exception('wsMaxReconnectAttempts=${AppConfig.wsMaxReconnectAttempts}'),
        context: {'solicitud_id': '$_solicitudId'},
      );
      return;
    }

    final delay = resiliente
        ? retrasoExponencial(_reconnectAttempts, esperaMaxima)
        : AppConfig.wsReconnectDelay *
            (1 + _reconnectAttempts).clamp(1, 10).toDouble();
    _reconnectAttempts++;

    AppLogger.warning('WsService: programando reconexión', context: {
      'solicitud_id': '$_solicitudId',
      'intento': '$_reconnectAttempts',
      'delay_ms': '${delay.inMilliseconds}',
    });

    // Dos fallos seguidos: puede ser una sesión revocada y no la red. Se pregunta al servidor.
    if (resiliente && _reconnectAttempts >= 2 && verificarSesion != null) {
      unawaited(_verificar());
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _doConnect);
  }

  Future<void> _verificar() async {
    try {
      await verificarSesion!();
    } on Object catch (e) {
      AppLogger.warning('WsService: verificación de sesión fallida',
          context: {'error': '$e'});
    }
  }

  /// Espera de la reconexión número [intento] (0 = primera): base × 2^intento, con tope.
  static Duration retrasoExponencial(int intento, Duration tope) {
    final base = AppConfig.wsReconnectDelay.inMilliseconds;
    final ms = base * (1 << intento.clamp(0, 10));
    final limite = tope.inMilliseconds;
    return Duration(milliseconds: ms > limite ? limite : ms);
  }

  // ── Enviar ─────────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } on Exception catch (e) {
      AppLogger.warning('WsService: no se pudo enviar mensaje',
          context: {'tipo': data['tipo']?.toString() ?? '?', 'error': '$e'});
    }
  }

  void sendGps(double lat, double lng, {DateTime? medidaEn}) {
    // `t`: la hora en que el telefono midio la posicion (milisegundos); es la que se guarda.
    _send({
      'tipo': 'GPS',
      'lat': lat,
      'lng': lng,
      't': (medidaEn ?? DateTime.now()).millisecondsSinceEpoch,
    });
  }

  // ── Desconectar ────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    _intentionalClose = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _cleanChannel();
    await _controller?.close();
    _controller = null;
  }

  void _cleanChannel() {
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
