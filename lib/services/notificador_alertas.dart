import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/textos_demo_alertas.dart';
import '../models/alerta_ruta.dart';
import 'log_service.dart';

/// Notificaciones del sistema de la alerta de ruta prohibida. Es una interfaz para poder probar la
/// lógica (deduplicación, permisos, apertura) sin plugins ni teléfono.
abstract class NotificadorAlertas {
  /// Prepara el canal y registra qué hacer cuando el usuario toca una notificación.
  Future<void> iniciar({required void Function(AlertaRuta) alTocar});

  /// Alerta cuya notificación abrió la app desde cero (app cerrada), o null.
  Future<AlertaRuta?> alertaDeLanzamiento();

  /// Si el sistema permite mostrar notificaciones (en Android 13+ exige permiso).
  Future<bool> permitidas();

  /// Pide el permiso del sistema. Devuelve si quedó concedido.
  Future<bool> pedirPermiso();

  Future<void> mostrar(AlertaRuta alerta);

  Future<void> cancelarTodas();
}

/// No hace nada: la app de operación y las pruebas.
class NotificadorNulo implements NotificadorAlertas {
  const NotificadorNulo();

  @override
  Future<void> iniciar({required void Function(AlertaRuta) alTocar}) async {}
  @override
  Future<AlertaRuta?> alertaDeLanzamiento() async => null;
  @override
  Future<bool> permitidas() async => true;
  @override
  Future<bool> pedirPermiso() async => true;
  @override
  Future<void> mostrar(AlertaRuta alerta) async {}
  @override
  Future<void> cancelarTodas() async {}
}

/// Implementación con `flutter_local_notifications` (BSD-3). Canal de importancia máxima con
/// sonido y vibración, visible en la pantalla de bloqueo.
class NotificadorLocal implements NotificadorAlertas {
  // El id del canal cambia si se cambian sonido/vibración: Android no deja modificar un canal ya
  // creado.
  static const String canalId = 'alerta_ruta_v1';
  static const int _idNotificacion = 4100;

  final FlutterLocalNotificationsPlugin _plugin;

  NotificadorLocal([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> iniciar({required void Function(AlertaRuta) alTocar}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (resp) {
        final alerta = AlertaRuta.dePayload(resp.payload);
        if (alerta != null) alTocar(alerta);
      },
    );
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        canalId,
        TextosAlertaRuta.canalNombre,
        description: TextosAlertaRuta.canalDescripcion,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: _vibracion,
      ),
    );
  }

  static final Int64List _vibracion =
      Int64List.fromList(<int>[0, 500, 250, 500, 250, 800]);

  @override
  Future<AlertaRuta?> alertaDeLanzamiento() async {
    final detalles = await _plugin.getNotificationAppLaunchDetails();
    if (detalles == null || !detalles.didNotificationLaunchApp) return null;
    return AlertaRuta.dePayload(detalles.notificationResponse?.payload);
  }

  @override
  Future<bool> permitidas() async =>
      await _android?.areNotificationsEnabled() ?? true;

  @override
  Future<bool> pedirPermiso() async =>
      await _android?.requestNotificationsPermission() ?? true;

  @override
  Future<void> mostrar(AlertaRuta alerta) async {
    try {
      await _plugin.show(
        id: _idNotificacion,
        title: TextosAlertaRuta.notificacionTitulo,
        body: alerta.texto,
        payload: alerta.toPayload(),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            canalId,
            TextosAlertaRuta.canalNombre,
            channelDescription: TextosAlertaRuta.canalDescripcion,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
            vibrationPattern: _vibracion,
            styleInformation: BigTextStyleInformation(alerta.texto),
            ticker: TextosAlertaRuta.notificacionTitulo,
            // Sin fullScreenIntent a propósito: desde Android 14 solo lo conceden por defecto las
            // apps de llamadas y alarmas; el aviso emergente con sonido ya llega con la pantalla
            // bloqueada.
            autoCancel: true,
          ),
        ),
      );
    } on Object catch (e, st) {
      AppLogger.error('Notificador: no se pudo mostrar la alerta', e,
          stackTrace: st);
    }
  }

  @override
  Future<void> cancelarTodas() => _plugin.cancel(id: _idNotificacion);
}
