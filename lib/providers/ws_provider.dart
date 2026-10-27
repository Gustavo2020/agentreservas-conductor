import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/seguimiento_service.dart';
import '../services/ubicacion_fuente.dart';
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
  final PosicionSimulada? _simulada;

  /// [simulada]: en modo demo, donde se guarda la última posición del vehículo que manda el
  /// servidor (la lee [UbicacionDemo]).
  WsProvider(this._ws, {PosicionSimulada? simulada}) : _simulada = simulada;

  EstadoViajeActivo _estado = EstadoViajeActivo.esperandoInicio;
  bool _chequeoSolicitado = false;
  bool _solicitudCancelada = false;
  String? _mensajeCancelacion;
  bool _checklistAprobado = false;
  String? _mensajeChecklistAprobacion;
  // La decision del revisor puede ser RECHAZAR: el aviso es el mismo mensaje con otro `estado`.
  // Tratar todo aviso como una aprobacion le decia al conductor que podia salir con un checklist
  // rechazado.
  bool _checklistRechazado = false;
  String? _mensajeChecklistRechazo;
  bool _viajeConfirmadoPorSolicitante = false;
  bool _viajeTerminado = false;
  // Aviso de que el vehículo entró a un tramo prohibido por operaciones.
  bool _tramoProhibido = false;
  String? _mensajeTramoProhibido;
  String? _alternativaTramo;
  // Posición del vehículo que manda el servidor y el rastro recorrido (se usa en modo demo).
  MuestraGps? _posicionVehiculo;
  final List<MuestraGps> _rastro = [];
  static const int _maxRastro = 400;
  StreamSubscription<WsMensaje>? _sub;

  bool get tramoProhibido => _tramoProhibido;
  String? get mensajeTramoProhibido => _mensajeTramoProhibido;
  String? get alternativaTramo => _alternativaTramo;
  MuestraGps? get posicionVehiculo => _posicionVehiculo;
  List<MuestraGps> get rastro => List.unmodifiable(_rastro);

  EstadoViajeActivo get estado => _estado;
  bool get chequeoSolicitado => _chequeoSolicitado;
  bool get enModoPanico => _estado == EstadoViajeActivo.modoPanico;
  bool get solicitudCancelada => _solicitudCancelada;
  String? get mensajeCancelacion => _mensajeCancelacion;
  bool get checklistAprobado => _checklistAprobado;
  bool get checklistRechazado => _checklistRechazado;
  String? get mensajeChecklistRechazo => _mensajeChecklistRechazo;
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

  void limpiarChecklistRechazado() {
    _checklistRechazado = false;
    _mensajeChecklistRechazo = null;
    notifyListeners();
  }

  void limpiarViajeConfirmado() {
    _viajeConfirmadoPorSolicitante = false;
    notifyListeners();
  }

  void limpiarTramoProhibido() {
    _tramoProhibido = false;
    _mensajeTramoProhibido = null;
    _alternativaTramo = null;
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
    _tramoProhibido = false;
    _posicionVehiculo = null;
    _rastro.clear();
    _simulada?.ultima = null;
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
        // `estado` es APROBADO o RECHAZADO (lo manda el servidor); sin él, por compatibilidad con
        // avisos antiguos, se toma como aprobado.
        final estado = msg.data['estado'] as String? ?? 'APROBADO';
        if (estado == 'RECHAZADO') {
          _checklistRechazado = true;
          _mensajeChecklistRechazo = msg.data['mensaje'] as String?;
        } else {
          _checklistAprobado = true;
          _mensajeChecklistAprobacion = msg.data['mensaje'] as String?;
        }
        notifyListeners();
      case WsMensajeTipo.tramoProhibido:
        _tramoProhibido = true;
        _mensajeTramoProhibido = msg.data['mensaje'] as String?;
        final alt = msg.data['alternativa'];
        _alternativaTramo = alt is String && alt.isNotEmpty ? alt : null;
        notifyListeners();
      case WsMensajeTipo.posicionVehiculo:
        final lat = msg.data['lat'];
        final lng = msg.data['lng'];
        if (lat is! num || lng is! num) break;
        final punto =
            MuestraGps(lat.toDouble(), lng.toDouble(), DateTime.now());
        _posicionVehiculo = punto;
        _simulada?.ultima = punto;
        _rastro.add(punto);
        if (_rastro.length > _maxRastro) _rastro.removeAt(0);
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
