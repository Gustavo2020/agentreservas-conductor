import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../config/textos_demo_alertas.dart';
import 'log_service.dart';

/// Servicio en primer plano de Android que mantiene viva la app (y con ella el WebSocket) mientras
/// hay un viaje en curso, con la pantalla apagada o la app minimizada. Interfaz para poder probar
/// la lógica sin teléfono.
abstract class ServicioViaje {
  Future<bool> iniciar();
  Future<void> detener();

  /// Si el sistema ya dejó a la app fuera del ahorro agresivo de batería.
  Future<bool> bateriaSinRestricciones();

  /// Abre el diálogo del sistema para excluir la app del ahorro de batería.
  Future<void> pedirSinRestriccionesDeBateria();
}

/// No hace nada: la app de operación y las pruebas.
class ServicioViajeNulo implements ServicioViaje {
  const ServicioViajeNulo();

  @override
  Future<bool> iniciar() async => false;
  @override
  Future<void> detener() async {}
  @override
  Future<bool> bateriaSinRestricciones() async => true;
  @override
  Future<void> pedirSinRestriccionesDeBateria() async {}
}

/// El servicio no ejecuta lógica propia: el WebSocket sigue viviendo en el isolate principal. El
/// servicio solo mantiene el proceso en primer plano (con wakelock y wifi lock) para que Android
/// no lo congele ni lo mate al minimizar.
@pragma('vm:entry-point')
void iniciarServicioViaje() {
  FlutterForegroundTask.setTaskHandler(_ManejadorViaje());
}

class _ManejadorViaje extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class ServicioViajePrimerPlano implements ServicioViaje {
  static const int _idServicio = 4200;
  static const String canalId = 'viaje_en_curso_v1';

  bool _configurado = false;

  /// Una vez por arranque de la app, antes de usar el servicio.
  static void prepararPuerto() => FlutterForegroundTask.initCommunicationPort();

  void _configurar() {
    if (_configurado) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: canalId,
        channelName: TextosAlertaRuta.viajeCanalNombre,
        channelDescription: TextosAlertaRuta.viajeCanalDescripcion,
        // Discreta: sin sonido ni vibración, importancia baja.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // No se relanza solo al reiniciar el teléfono: sin sesión ni viaje no tiene sentido.
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
        // Si el usuario quita la app de recientes, el servicio se detiene con ella.
        stopWithTask: true,
      ),
    );
    _configurado = true;
  }

  @override
  Future<bool> iniciar() async {
    try {
      _configurar();
      if (await FlutterForegroundTask.isRunningService) return true;
      final r = await FlutterForegroundTask.startService(
        serviceId: _idServicio,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: TextosAlertaRuta.viajeTitulo,
        notificationText: TextosAlertaRuta.viajeTexto,
        callback: iniciarServicioViaje,
      );
      final ok = r is ServiceRequestSuccess;
      if (!ok) {
        AppLogger.warning('ServicioViaje: no arrancó',
            context: {'resultado': '$r'});
      }
      return ok;
    } on Object catch (e, st) {
      AppLogger.error('ServicioViaje: fallo al iniciar', e, stackTrace: st);
      return false;
    }
  }

  @override
  Future<void> detener() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } on Object catch (e, st) {
      AppLogger.error('ServicioViaje: fallo al detener', e, stackTrace: st);
    }
  }

  @override
  Future<bool> bateriaSinRestricciones() async {
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } on Object {
      return true;
    }
  }

  @override
  Future<void> pedirSinRestriccionesDeBateria() async {
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } on Object catch (e, st) {
      AppLogger.error('ServicioViaje: ajuste de batería', e, stackTrace: st);
    }
  }
}
