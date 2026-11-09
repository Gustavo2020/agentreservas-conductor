import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alerta_ruta.dart';
import '../providers/ws_provider.dart';
import 'log_service.dart';
import 'notificador_alertas.dart';
import 'servicio_viaje.dart';

/// Pequeño almacén de banderas (para «ya se explicó el permiso»).
abstract class AlmacenBanderas {
  Future<String?> leer(String clave);
  Future<void> guardar(String clave, String valor);
}

class AlmacenBanderasPrefs implements AlmacenBanderas {
  const AlmacenBanderasPrefs();

  @override
  Future<String?> leer(String clave) async =>
      (await SharedPreferences.getInstance()).getString(clave);

  @override
  Future<void> guardar(String clave, String valor) async {
    await (await SharedPreferences.getInstance()).setString(clave, valor);
  }
}

/// Cerebro de la alerta de ruta prohibida en la APK de demostración. Vive a nivel de la app (no de
/// una pantalla), por eso el aviso llega sea cual sea la pantalla abierta:
///  * al llegar `TRAMO_PROHIBIDO` por el WebSocket lo deduplica, lanza la notificación del sistema
///    y deja la alerta lista para que la puerta de la app muestre el diálogo;
///  * mientras hay un viaje conectado mantiene el servicio en primer plano (el WebSocket sigue
///    vivo con la app minimizada o la pantalla bloqueada);
///  * al terminar el viaje o la sesión lo apaga todo.
class GestorAlertaRuta extends ChangeNotifier {
  static const String _clavePermisoNotif = 'demo_permiso_notif_pedido_v1';
  static const String _claveBateria = 'demo_permiso_bateria_pedido_v1';
  static const int _maxExplicacionesNotif = 2;

  final WsProvider ws;
  final NotificadorAlertas notificador;
  final ServicioViaje servicio;
  final AlmacenBanderas almacen;
  final DateTime Function() _ahora;

  /// Sin identificador del servidor, dos avisos iguales dentro de esta ventana son el mismo
  /// (reenvío del servidor). Pasada la ventana, uno igual es una alerta nueva (el vehículo salió
  /// del tramo y volvió a entrar).
  final Duration ventanaSinId;

  GestorAlertaRuta({
    required this.ws,
    required this.notificador,
    required this.servicio,
    required this.almacen,
    DateTime Function()? ahora,
    this.ventanaSinId = const Duration(minutes: 10),
  }) : _ahora = ahora ?? DateTime.now;

  final Map<String, DateTime> _vistos = {};
  AlertaRuta? _pendiente;
  String? _idMostrando;
  bool _servicioActivo = false;
  int? _generacionCerrada;
  bool _iniciado = false;

  /// Alerta lista para mostrarse en un diálogo (la puerta de la app la toma con [tomarPendiente]).
  AlertaRuta? get pendiente => _pendiente;
  bool get servicioActivo => _servicioActivo;

  Future<void> iniciar() async {
    if (_iniciado) return;
    _iniciado = true;
    ws.addListener(_enWs);
    try {
      await notificador.iniciar(alTocar: abrirDesdeNotificacion);
      final deLanzamiento = await notificador.alertaDeLanzamiento();
      if (deLanzamiento != null) abrirDesdeNotificacion(deLanzamiento);
    } on Object catch (e, st) {
      AppLogger.error(
          'GestorAlertaRuta: no se pudo preparar las notificaciones', e,
          stackTrace: st);
    }
  }

  @override
  void dispose() {
    ws.removeListener(_enWs);
    super.dispose();
  }

  // ── Mensajes del servidor ──────────────────────────────────────────────────

  void _enWs() {
    final alerta = ws.alertaTramo;
    if (ws.tramoProhibido && alerta != null) {
      ws.limpiarTramoProhibido();
      unawaited(atender(alerta));
    }
    if (ws.viajeTerminado || ws.solicitudCancelada) {
      // El viaje acabó: no hay nada que vigilar. Las pantallas siguen leyendo sus banderas.
      unawaited(viajeCerrado());
      return;
    }
    _sincronizarServicio();
  }

  /// Procesa una alerta: la ignora si ya se atendió; si es nueva, notifica y la deja pendiente.
  Future<void> atender(AlertaRuta alerta) async {
    if (_esDuplicada(alerta)) {
      AppLogger.info('GestorAlertaRuta: alerta repetida ignorada',
          context: {'id': alerta.id});
      return;
    }
    _pendiente = alerta;
    notifyListeners();
    // La notificación sale de inmediato; el diálogo lo muestra la puerta si la app está abierta.
    await notificador.mostrar(alerta);
  }

  bool _esDuplicada(AlertaRuta alerta) {
    final ahora = _ahora();
    // Las claves sin id del servidor caducan con la ventana; las que sí lo traen, no.
    _vistos.removeWhere((id, cuando) =>
        !_idsFijos.contains(id) && ahora.difference(cuando) > ventanaSinId);
    if (_vistos.containsKey(alerta.id)) return true;
    _vistos[alerta.id] = ahora;
    if (alerta.idDelServidor) _idsFijos.add(alerta.id);
    return false;
  }

  // Los ids que manda el servidor no caducan por ventana.
  final Set<String> _idsFijos = {};

  // ── Apertura desde la notificación ─────────────────────────────────────────

  /// El usuario tocó la notificación (app en segundo plano, bloqueada o cerrada).
  void abrirDesdeNotificacion(AlertaRuta alerta) {
    // Si ese mismo aviso ya está en pantalla no se muestra otra vez.
    if (_idMostrando == alerta.id) return;
    _pendiente = alerta;
    notifyListeners();
  }

  /// La puerta de la app toma la alerta para mostrarla; queda marcada como «en pantalla».
  AlertaRuta? tomarPendiente() {
    final a = _pendiente;
    if (a == null) return null;
    _pendiente = null;
    _idMostrando = a.id;
    return a;
  }

  /// El conductor pulsó «Entendido»: la notificación del sistema ya no hace falta.
  Future<void> alertaAtendida() async {
    _idMostrando = null;
    await notificador.cancelarTodas();
  }

  // ── Servicio en primer plano ───────────────────────────────────────────────

  bool get _hayViajeEnCurso =>
      ws.solicitudActiva != null &&
      ws.generacion != _generacionCerrada &&
      !ws.viajeTerminado &&
      !ws.solicitudCancelada;

  /// Arranca o detiene el servicio según haya viaje conectado. La app llama también esto al volver
  /// al primer plano: Android 12+ no deja arrancar el servicio desde segundo plano, así que un
  /// intento fallido se repite en cuanto la app se ve.
  void sincronizar() => _sincronizarServicio();

  void _sincronizarServicio() {
    if (_hayViajeEnCurso && !_servicioActivo) {
      unawaited(_arrancarServicio());
    }
  }

  Future<void> _arrancarServicio() async {
    _servicioActivo = true;
    final ok = await servicio.iniciar();
    // Si falla se reintenta en la próxima sincronización.
    if (!ok) {
      _servicioActivo = false;
    }
  }

  /// El viaje terminó (cierre del conductor, del solicitante o cancelación): se apaga todo.
  Future<void> viajeCerrado() async {
    _generacionCerrada = ws.generacion;
    if (_servicioActivo) {
      _servicioActivo = false;
      await servicio.detener();
    }
    await notificador.cancelarTodas();
    if (ws.solicitudActiva != null) await ws.desconectar();
  }

  /// La sesión terminó (cierre manual, vencida, 401): se borra todo rastro del viaje anterior.
  Future<void> reiniciar() async {
    _pendiente = null;
    _idMostrando = null;
    _vistos.clear();
    _idsFijos.clear();
    _generacionCerrada = null;
    _servicioActivo = false;
    await servicio.detener();
    await notificador.cancelarTodas();
    await ws.reiniciar();
    notifyListeners();
  }

  // ── Permisos ───────────────────────────────────────────────────────────────

  /// Pide, con una explicación breve, el permiso de notificaciones (solo si falta y hasta
  /// [_maxExplicacionesNotif] veces) y la exclusión del ahorro de batería (una sola vez).
  Future<void> prepararPermisos({
    required Future<bool> Function() explicarNotificaciones,
    required Future<bool> Function() explicarBateria,
  }) async {
    try {
      if (!await notificador.permitidas()) {
        final veces =
            int.tryParse(await almacen.leer(_clavePermisoNotif) ?? '') ?? 0;
        if (veces < _maxExplicacionesNotif) {
          await almacen.guardar(_clavePermisoNotif, '${veces + 1}');
          if (await explicarNotificaciones()) await notificador.pedirPermiso();
        }
      }
      if (await almacen.leer(_claveBateria) != '1' &&
          !await servicio.bateriaSinRestricciones()) {
        await almacen.guardar(_claveBateria, '1');
        if (await explicarBateria()) {
          await servicio.pedirSinRestriccionesDeBateria();
        }
      }
    } on Object catch (e, st) {
      AppLogger.error('GestorAlertaRuta: permisos', e, stackTrace: st);
    }
  }
}
