import 'package:geolocator/geolocator.dart';

import 'log_service.dart';
import 'panico_service.dart';
import 'seguimiento_service.dart';

/// Qué pasó al pedir el seguimiento del viaje.
enum ArranqueSeguimiento { activo, sinPermiso, sinGps }

/// Lo que la pantalla necesita del seguimiento y del pánico, con los permisos del teléfono
/// resueltos. La pantalla no toca Geolocator: así se puede probar con falsos.
class SeguimientoController {
  final SeguimientoService seguimiento;
  final PanicoService panico;
  final Future<LocationPermission> Function() pedirPermiso;
  final Future<bool> Function() gpsEncendido;
  final Future<MuestraGps?> Function() posicionAhora;

  SeguimientoController({
    required this.seguimiento,
    required this.panico,
    Future<LocationPermission> Function()? pedirPermiso,
    Future<bool> Function()? gpsEncendido,
    Future<MuestraGps?> Function()? posicionAhora,
  })  : pedirPermiso = pedirPermiso ?? _permisoReal,
        gpsEncendido = gpsEncendido ?? Geolocator.isLocationServiceEnabled,
        posicionAhora = posicionAhora ?? _posicionReal;

  static Future<LocationPermission> _permisoReal() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p;
  }

  static Future<MuestraGps?> _posicionReal() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
      return MuestraGps(p.latitude, p.longitude, p.timestamp);
    } on Object {
      final u = await Geolocator.getLastKnownPosition();
      return u == null
          ? null
          : MuestraGps(u.latitude, u.longitude, u.timestamp);
    }
  }

  /// Empieza a seguir el viaje. Sin permiso o con el GPS apagado no se puede: se dice, para que la
  /// pantalla le pida al conductor que lo active (no se falla en silencio).
  Future<ArranqueSeguimiento> iniciar(int solicitudId) async {
    final permiso = await pedirPermiso();
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      return ArranqueSeguimiento.sinPermiso;
    }
    if (!await gpsEncendido()) return ArranqueSeguimiento.sinGps;
    await seguimiento.iniciar(solicitudId);
    return ArranqueSeguimiento.activo;
  }

  Future<void> detener() => seguimiento.detener();

  /// El botón de pánico. Usa la última posición conocida si es reciente (instantánea: en una
  /// emergencia no se espera al GPS); si no, la pide al teléfono. Sin ninguna posición no se puede
  /// pedir ayuda (el servidor la exige): devuelve `null` para que la pantalla avise.
  Future<ResultadoPanico?> pulsarPanico(int solicitudId) async {
    final ultima = seguimiento.ultimaConocida;
    MuestraGps? punto = ultima;
    final reciente = ultima != null &&
        DateTime.now().difference(ultima.medidaEn) < const Duration(minutes: 2);
    if (!reciente) punto = await posicionAhora() ?? ultima;
    if (punto == null) {
      AppLogger.warning('Pánico: sin posición para enviar');
      return null;
    }
    return panico.pulsar(solicitudId, punto.lat, punto.lng);
  }
}
