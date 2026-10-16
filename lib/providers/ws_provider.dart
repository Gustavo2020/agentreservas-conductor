import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/ws_service.dart';

/// Estado del viaje activo desde perspectiva del conductor.
enum EstadoViajeActivo {
  esperandoInicio,
  esperandoConfirmacionUsuario,
  viajeConfirmado,
  enRuta,
  esperandoFinalizacion,
  modoPanico,
}

class WsProvider extends ChangeNotifier {
  final WsService _ws;

  WsProvider(this._ws);

  EstadoViajeActivo _estado = EstadoViajeActivo.esperandoInicio;
  bool _chequeoSolicitado = false;
  bool _solicitudCancelada = false;
  String? _mensajeCancelacion;
  bool _checklistAprobado = false;
  String? _mensajeChecklistAprobacion;
  bool _viajeConfirmadoPorSolicitante = false;
  bool _viajeTerminado = false;
  StreamSubscription<WsMensaje>? _sub;

  EstadoViajeActivo get estado => _estado;
  bool get chequeoSolicitado => _chequeoSolicitado;
  bool get enModoPanico => _estado == EstadoViajeActivo.modoPanico;
  bool get solicitudCancelada => _solicitudCancelada;
  String? get mensajeCancelacion => _mensajeCancelacion;
  bool get checklistAprobado => _checklistAprobado;
  String? get mensajeChecklistAprobacion => _mensajeChecklistAprobacion;
  bool get viajeConfirmadoPorSolicitante => _viajeConfirmadoPorSolicitante;
  bool get viajeTerminado => _viajeTerminado;

  void limpiarCancelacion() {
    _solicitudCancelada = false;
    _mensajeCancelacion = null;
    notifyListeners();
  }

  void limpiarChecklistAprobado() {
    _checklistAprobado = false;
    _mensajeChecklistAprobacion = null;
    notifyListeners();
  }

  void limpiarViajeConfirmado() {
    _viajeConfirmadoPorSolicitante = false;
    notifyListeners();
  }

  void limpiarViajeTerminado() {
    _viajeTerminado = false;
    notifyListeners();
  }

  // ── Conectar ───────────────────────────────────────────────────────────────

  Future<void> conectar(int solicitudId) async {
    // Cancelar suscripción anterior antes de reasignar para evitar listeners
    // duplicados si conectar() se llama más de una vez en el mismo ciclo.
    await _sub?.cancel();
    _sub = null;
    // Reiniciar estado: evita que estado stale de sesiones anteriores
    // (enRuta, viajeConfirmado, etc.) salte el flujo de abordaje.
    _estado = EstadoViajeActivo.esperandoInicio;
    _chequeoSolicitado = false;
    _viajeConfirmadoPorSolicitante = false;
    _viajeTerminado = false;
    notifyListeners();
    await _ws.connect(solicitudId);
    _sub = _ws.stream.listen(_onMensaje);
  }

  void _onMensaje(WsMensaje msg) {
    switch (msg.tipo) {
      case WsMensajeTipo.viajeConfirmado:
        // Solo aceptar si el conductor ya reportó estar en sitio;
        // rechaza mensajes encolados de sesiones anteriores.
        // El screen escuchará este flag y llamará iniciarViaje() automáticamente.
        if (_estado == EstadoViajeActivo.esperandoConfirmacionUsuario) {
          _viajeConfirmadoPorSolicitante = true;
          notifyListeners();
        }
      case WsMensajeTipo.chequeoRequest:
        _chequeoSolicitado = true;
        notifyListeners();
      case WsMensajeTipo.viajeTerminado:
        _viajeTerminado = true;
        notifyListeners();
      case WsMensajeTipo.solicitudCancelada:
        _solicitudCancelada = true;
        _mensajeCancelacion =
            msg.data['mensaje'] as String? ?? 'El viaje ha sido cancelado.';
        notifyListeners();
      case WsMensajeTipo.aprobacionChecklist:
        _checklistAprobado = true;
        _mensajeChecklistAprobacion = msg.data['mensaje'] as String?;
        notifyListeners();
      default:
        break;
    }
  }

  // ── Acciones ───────────────────────────────────────────────────────────────

  /// Restaura el estado del WsProvider a partir de los eventos de trazabilidad.
  ///
  /// Se usa tras un hot-restart o al navegar de vuelta a [ViajeActivoScreen].
  /// Usa los eventos de trazabilidad (no `estado == 'EN_CURSO'`) porque el
  /// backend establece EN_CURSO al asignar el vehículo, antes de que el
  /// conductor haya iniciado el viaje realmente.
  ///
  /// Prioridad:
  ///   1. [viajeIniciado]      → enRuta
  ///   2. [abordajeConfirmado] → dispara viajeConfirmadoPorSolicitante (el screen
  ///                             llama _iniciarViaje() al ver el flag)
  ///   3. [enSitio]            → esperandoConfirmacionUsuario
  ///   4. ninguno              → esperandoInicio (sin cambio)
  void recuperarEstadoDeViaje({
    required bool viajeIniciado,
    required bool enSitio,
    required bool abordajeConfirmado,
  }) {
    // Permitir recuperación desde esperandoInicio O esperandoConfirmacionUsuario.
    // El caso crítico: conductor ya reportó "en sitio" (_estado ==
    // esperandoConfirmacionUsuario) pero el WS perdió el mensaje VIAJE_CONFIRMADO.
    // Al pulsar "Refrescar", abordajeConfirmado=true → activar el flag para que
    // _onWsChange llame _iniciarViaje() automáticamente.
    final recuperable = _estado == EstadoViajeActivo.esperandoInicio ||
        _estado == EstadoViajeActivo.esperandoConfirmacionUsuario;
    if (!recuperable) return;

    if (viajeIniciado) {
      _estado = EstadoViajeActivo.enRuta;
      notifyListeners();
    } else if (abordajeConfirmado) {
      // El pasajero confirmó pero el WS no llegó (o el conductor ya estaba
      // esperando). Forzar el flag para que el screen llame _iniciarViaje().
      _estado = EstadoViajeActivo.esperandoConfirmacionUsuario;
      _viajeConfirmadoPorSolicitante = true;
      notifyListeners();
    } else if (enSitio && _estado == EstadoViajeActivo.esperandoInicio) {
      // Solo avanzar a esperandoConfirmacion si aún estamos en esperandoInicio.
      _estado = EstadoViajeActivo.esperandoConfirmacionUsuario;
      notifyListeners();
    }
  }

  void marcarEnSitio() {
    _estado = EstadoViajeActivo.esperandoConfirmacionUsuario;
    notifyListeners();
  }

  void marcarViajeIniciado() {
    _estado = EstadoViajeActivo.enRuta;
    notifyListeners();
  }

  void marcarEsperandoFinalizacion() {
    if (_estado == EstadoViajeActivo.esperandoFinalizacion) return;
    _estado = EstadoViajeActivo.esperandoFinalizacion;
    notifyListeners();
  }

  void activarModoPanico() {
    _estado = EstadoViajeActivo.modoPanico;
    notifyListeners();
  }

  void desactivarModoPanico() {
    _estado = EstadoViajeActivo.enRuta;
    notifyListeners();
  }

  void resolverChequeo() {
    _chequeoSolicitado = false;
    notifyListeners();
  }

  void sendGps(double lat, double lng) {
    _ws.sendGps(lat, lng);
  }

  // ── Desconectar ────────────────────────────────────────────────────────────

  Future<void> desconectar() async {
    await _sub?.cancel();
    await _ws.disconnect();
  }

  @override
  void dispose() {
    desconectar();
    super.dispose();
  }
}
