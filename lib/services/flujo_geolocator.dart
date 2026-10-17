import 'package:geolocator/geolocator.dart';

import 'seguimiento_service.dart';

/// El flujo REAL de posiciones del teléfono. En Android lleva un servicio en PRIMER PLANO con su
/// notificación: así el sistema no detiene el seguimiento cuando el conductor minimiza la app o
/// apaga la pantalla (sin él, en pocos minutos Android lo mata y el viaje queda sin rastro).
Stream<MuestraGps> flujoGeolocator() {
  final ajustes = AndroidSettings(
    accuracy: LocationAccuracy.high,
    // Se entrega aunque el vehículo esté quieto (cada 10 s): la ausencia de posiciones es lo que
    // el servidor lee como «sin señal», y un vehículo detenido no debe parecer desconectado.
    distanceFilter: 0,
    intervalDuration: const Duration(seconds: 10),
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'Viaje en curso',
      notificationText: 'Compartiendo tu ubicación con operaciones',
      notificationChannelName: 'Seguimiento del viaje',
      enableWakeLock: true,
    ),
  );
  return Geolocator.getPositionStream(locationSettings: ajustes).map(
    (p) => MuestraGps(p.latitude, p.longitude, p.timestamp),
  );
}
