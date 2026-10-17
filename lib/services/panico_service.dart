import 'dart:async';

import 'log_service.dart';

/// Qué pasó con una pulsación de pánico.
enum ResultadoPanico {
  /// El servidor confirmó que la ayuda quedó pedida.
  confirmado,

  /// No hubo señal o el servidor no respondió: se reintenta.
  reintentar,

  /// El servidor la rechazó de forma definitiva (el viaje ya no está en curso, o no es de este
  /// conductor): reintentar no sirve. Hay que avisar para que el conductor llame a operaciones.
  rechazado,
}

/// Cómo se manda la pulsación de pánico al servidor.
typedef EnviarPanico = Future<ResultadoPanico> Function(
  int solicitudId,
  double lat,
  double lng,
);

/// El botón de pánico: pedir ayuda no puede depender de que haya señal en ese instante. La
/// pulsación se intenta enseguida y, si no llega, se REINTENTA cada pocos segundos hasta que el
/// servidor la confirma (o la rechaza). Una pulsación perdida por una caída de señal es justo
/// cuando más se necesita.
class PanicoService {
  final EnviarPanico enviar;
  final Duration reintentoCada;

  PanicoService({
    required this.enviar,
    this.reintentoCada = const Duration(seconds: 5),
  });

  Timer? _temporizador;
  bool _pendiente = false;

  // Numero de la pulsacion vigente: si se pulsa de nuevo mientras la anterior esperaba respuesta,
  // la anterior NO debe programar su propio reintento (quedarian dos temporizadores insistiendo).
  int _ronda = 0;

  /// Hay una pulsación que aún no llegó al servidor.
  bool get pendiente => _pendiente;

  /// Pulsa el pánico. Devuelve el resultado del primer intento; si fue `reintentar`, queda
  /// pendiente y se reintenta sola (no hace falta volver a pulsar).
  Future<ResultadoPanico> pulsar(
      int solicitudId, double lat, double lng) async {
    _cancelar();
    final ronda = ++_ronda;
    final r = await _intentar(solicitudId, lat, lng);
    if (r != ResultadoPanico.reintentar) return r;
    // Otra pulsacion tomo el relevo mientras esta esperaba: esa se encarga del reintento.
    if (ronda != _ronda) return r;
    _pendiente = true;
    AppLogger.warning('Pánico: sin confirmar, se reintenta', context: {
      'solicitud_id': '$solicitudId',
    });
    _temporizador = Timer.periodic(reintentoCada, (t) async {
      final otra = await _intentar(solicitudId, lat, lng);
      if (otra != ResultadoPanico.reintentar && ronda == _ronda) _cancelar();
    });
    return r;
  }

  Future<ResultadoPanico> _intentar(
      int solicitudId, double lat, double lng) async {
    try {
      return await enviar(solicitudId, lat, lng);
    } on Object catch (e) {
      AppLogger.warning('Pánico: fallo al enviar', context: {'e': '$e'});
      return ResultadoPanico.reintentar;
    }
  }

  void _cancelar() {
    _temporizador?.cancel();
    _temporizador = null;
    _pendiente = false;
  }

  void dispose() => _cancelar();
}
