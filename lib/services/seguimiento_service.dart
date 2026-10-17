import 'dart:async';

import 'cola_posiciones.dart';
import 'log_service.dart';

/// Una posición que entrega el sistema (el flujo real viene de Geolocator): coordenadas y la hora
/// en que el teléfono dice haberla medido.
class MuestraGps {
  final double lat;
  final double lng;
  final DateTime medidaEn;

  const MuestraGps(this.lat, this.lng, this.medidaEn);
}

/// Resultado de mandar un lote al servidor.
enum ResultadoLote {
  /// El servidor lo recibió: se quita de la cola.
  recibido,

  /// No hubo señal o el servidor no respondió: se conserva y se reintenta.
  reintentar,

  /// El servidor rechazó ESTE lote por mal formado (no por falta de señal): se quita y se sigue.
  /// Reintentarlo lo bloquearía para siempre, y con él todo lo que viene detrás.
  omitir,

  /// El servidor dice que este viaje ya no admite posiciones (cerrado, reasignado): se vacía la
  /// cola y se deja de seguir. Reintentar sería insistir con algo que no va a entrar nunca.
  descartar,
}

typedef EnviarLote = Future<ResultadoLote> Function(
  int solicitudId,
  List<PuntoGps> puntos,
);

/// Sigue la posición del conductor mientras el viaje está EN CURSO, aunque la app esté en segundo
/// plano, y la manda al servidor por lotes. Si no hay señal, las posiciones esperan en una cola
/// local (con su hora de medida) y se mandan al volver. El servidor decide cuáles guarda; aquí solo
/// se cuida no mandar de más y no perder lo medido.
class SeguimientoService {
  final ColaPosiciones cola;
  final Stream<MuestraGps> Function() abrirFlujo;
  final EnviarLote enviarLote;
  final DateTime Function() ahora;

  /// Separación mínima entre dos posiciones que se guardan: más seguido no aporta al mapa y gasta
  /// batería, datos y cola.
  final Duration separacionMinima;

  /// Cada cuánto se intenta vaciar la cola.
  final Duration cadaLote;

  /// Cuántos puntos van en un envío (el servidor acepta hasta 200).
  final int tamanoLote;

  SeguimientoService({
    required this.cola,
    required this.abrirFlujo,
    required this.enviarLote,
    DateTime Function()? ahora,
    this.separacionMinima = const Duration(seconds: 10),
    this.cadaLote = const Duration(seconds: 15),
    this.tamanoLote = 100,
  }) : ahora = ahora ?? DateTime.now;

  StreamSubscription<MuestraGps>? _suscripcion;
  Timer? _temporizador;
  int? _solicitudId;
  int? _ultimoMs;
  MuestraGps? _ultima;
  bool _enviando = false;

  bool get activo => _solicitudId != null;
  int? get solicitudId => _solicitudId;

  /// La última posición medida (para el botón de pánico: si no hay GPS al instante, esta sirve).
  MuestraGps? get ultimaConocida => _ultima;

  Future<void> iniciar(int solicitudId) async {
    // Ya se sigue este viaje: no se abre un segundo flujo (gastaría el doble de batería).
    if (_solicitudId == solicitudId) return;
    await detener();
    _solicitudId = solicitudId;
    _ultimoMs = null;
    await cola.cargar();
    _suscripcion = abrirFlujo().listen(
      _alMedir,
      onError: (Object e) =>
          AppLogger.warning('Seguimiento: error del GPS', context: {'e': '$e'}),
    );
    _temporizador = Timer.periodic(cadaLote, (_) => vaciarCola());
    // Lo que quedó de una sesión anterior (sin señal, app cerrada) se intenta mandar ya.
    unawaited(vaciarCola());
  }

  Future<void> detener() async {
    await _suscripcion?.cancel();
    _suscripcion = null;
    _temporizador?.cancel();
    _temporizador = null;
    _solicitudId = null;
  }

  Future<void> _alMedir(MuestraGps m) async {
    _ultima = m;
    final tMs = m.medidaEn.millisecondsSinceEpoch;
    final previo = _ultimoMs;
    // El umbral se mide con la hora de la MEDIDA, no con la del reloj: así dos muestras entregadas
    // juntas (el sistema las acumuló) no se cuentan como una sola ni se separan mal.
    if (previo != null &&
        (tMs - previo).abs() < separacionMinima.inMilliseconds) {
      return;
    }
    _ultimoMs = tMs;
    await cola.agregar(PuntoGps(m.lat, m.lng, tMs));
    // Con muchos puntos acumulados no se espera al temporizador.
    if (cola.longitud >= tamanoLote) unawaited(vaciarCola());
  }

  /// Manda lo que hay en la cola, en lotes, hasta vaciarla o hasta el primer fallo.
  Future<void> vaciarCola() async {
    final id = _solicitudId;
    if (id == null || _enviando) return;
    _enviando = true;
    try {
      while (!cola.vacia) {
        final lote = cola.proximoLote(tamanoLote);
        final r = await enviarLote(id, lote);
        if (r == ResultadoLote.recibido || r == ResultadoLote.omitir) {
          await cola.confirmar(lote.length);
        } else if (r == ResultadoLote.descartar) {
          await cola.vaciar();
          await detener();
          return;
        } else {
          return; // sin señal: se intenta en el próximo ciclo
        }
      }
    } finally {
      _enviando = false;
    }
  }
}
