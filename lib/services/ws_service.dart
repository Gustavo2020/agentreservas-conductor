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
  desconocido,
}

class WsMensaje {
  final WsMensajeTipo tipo;
  final Map<String, dynamic> data;

  const WsMensaje(this.tipo, this.data);

  static WsMensaje fromJson(Map<String, dynamic> json) {
    final tipo = json['tipo'] as String? ?? '';
    final t = switch (tipo) {
      'CHEQUEO_REQUEST'     => WsMensajeTipo.chequeoRequest,
      'VIAJE_CONFIRMADO'    => WsMensajeTipo.viajeConfirmado,
      'APROBACION_CHECKLIST'=> WsMensajeTipo.aprobacionChecklist,
      'APROBACION_SOPORTE'  => WsMensajeTipo.aprobacionSoporte,
      'SOLICITUD_CANCELADA' => WsMensajeTipo.solicitudCancelada,
      'VIAJE_FINALIZADO'    => WsMensajeTipo.viajeTerminado,
      'NOTIFICACION'        => WsMensajeTipo.notificacion,
      _                     => WsMensajeTipo.desconocido,
    };
    return WsMensaje(t, json);
  }
}

/// Gestiona la conexión WebSocket con reconexión automática + backoff.
class WsService {
  final AuthService _auth;

  WsService(this._auth);

  WebSocketChannel? _channel;
  StreamController<WsMensaje>? _controller;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  int _reconnectAttempts = 0;
  bool _intentionalClose = false;
  int? _solicitudId;

  Stream<WsMensaje> get stream =>
      _controller?.stream ?? const Stream.empty();

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
    if (token == null) return;

    final uri = Uri.parse(
      '${AppConfig.wsBaseUrl}/ws/conductor/$_solicitudId?token=$token',
    );

    AppLogger.info('WsService: conectando',
        context: {'solicitud_id': '$_solicitudId', 'intento': '$_reconnectAttempts'});

    try {
      _channel = WebSocketChannel.connect(uri);
      _reconnectAttempts = 0;

      // Escuchar mensajes
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // Ping cada 30s para mantener conexión viva
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _send({'tipo': 'PING'});
      });
    } on Exception catch (e, st) {
      AppLogger.error('WsService: error al conectar', e,
          stackTrace: st,
          context: {'solicitud_id': '$_solicitudId'});
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
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
    if (_reconnectAttempts >= AppConfig.wsMaxReconnectAttempts) {
      AppLogger.fatal(
        'WsService: máximo de reconexiones alcanzado',
        Exception('wsMaxReconnectAttempts=${AppConfig.wsMaxReconnectAttempts}'),
        context: {'solicitud_id': '$_solicitudId'},
      );
      return;
    }

    final delay = AppConfig.wsReconnectDelay *
        (1 + _reconnectAttempts).clamp(1, 10).toDouble();
    _reconnectAttempts++;

    AppLogger.warning('WsService: programando reconexión',
        context: {
          'solicitud_id': '$_solicitudId',
          'intento': '$_reconnectAttempts',
          'delay_ms': '${delay.inMilliseconds}',
        });

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _doConnect);
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

  void sendGps(double lat, double lng) {
    _send({'tipo': 'GPS', 'lat': lat, 'lng': lng});
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
