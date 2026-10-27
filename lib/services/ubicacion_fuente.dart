import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';
import 'flujo_geolocator.dart';
import 'seguimiento_service.dart';

/// De dónde sale la posición del vehículo. Las pantallas y el seguimiento piden la posición aquí y
/// no a Geolocator: así en la APK de demostración se puede reemplazar por la posición simulada
/// que genera el servidor, sin pedir permisos de ubicación al teléfono.
abstract class UbicacionFuente {
  const UbicacionFuente();

  /// true si la posición la genera el servidor (modo demo): el teléfono no envía su GPS.
  bool get esDemo;

  Future<LocationPermission> pedirPermiso();
  Future<bool> gpsEncendido();

  /// La posición de ahora, o null si no hay ninguna.
  Future<MuestraGps?> posicionAhora(
      {Duration limite = const Duration(seconds: 4)});

  /// El flujo continuo de posiciones (solo el real lo usa).
  Stream<MuestraGps> flujo();
}

/// El GPS real del teléfono (APK normal).
class UbicacionReal extends UbicacionFuente {
  const UbicacionReal();

  @override
  bool get esDemo => false;

  @override
  Future<LocationPermission> pedirPermiso() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p;
  }

  @override
  Future<bool> gpsEncendido() => Geolocator.isLocationServiceEnabled();

  @override
  Future<MuestraGps?> posicionAhora({
    Duration limite = const Duration(seconds: 4),
  }) async {
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: limite,
      );
      return MuestraGps(p.latitude, p.longitude, p.timestamp);
    } on Object {
      final u = await Geolocator.getLastKnownPosition();
      return u == null
          ? null
          : MuestraGps(u.latitude, u.longitude, u.timestamp);
    }
  }

  @override
  Stream<MuestraGps> flujo() => flujoGeolocator();
}

/// Guarda la última posición del vehículo simulado que llegó del servidor.
class PosicionSimulada {
  MuestraGps? ultima;
}

/// Modo demo: no toca el GPS ni pide permisos. La «posición actual» es la última que el servidor
/// mandó del viaje simulado; si todavía no llegó ninguna, el punto de partida de la demo.
class UbicacionDemo extends UbicacionFuente {
  final PosicionSimulada simulada;
  final DateTime Function() ahora;

  UbicacionDemo(this.simulada, {DateTime Function()? ahora})
      : ahora = ahora ?? DateTime.now;

  @override
  bool get esDemo => true;

  @override
  Future<LocationPermission> pedirPermiso() async => LocationPermission.always;

  @override
  Future<bool> gpsEncendido() async => true;

  @override
  Future<MuestraGps?> posicionAhora({
    Duration limite = const Duration(seconds: 4),
  }) async =>
      simulada.ultima ??
      MuestraGps(
        AppConfig.demoLatInicial,
        AppConfig.demoLngInicial,
        ahora(),
      );

  @override
  Stream<MuestraGps> flujo() => const Stream.empty();
}
