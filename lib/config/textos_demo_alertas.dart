/// Textos de cara al usuario de la alerta de ruta prohibida, sus permisos y el cierre de la
/// sesión de la demostración. Están todos aquí para que el dueño los apruebe en un solo lugar.
class TextosAlertaRuta {
  TextosAlertaRuta._();

  // Notificación de la alerta (canal de importancia máxima).
  static const String canalNombre = 'Alertas de ruta';
  static const String canalDescripcion =
      'Avisa de inmediato cuando el vehículo entra a un tramo prohibido.';
  static const String notificacionTitulo = 'Ruta prohibida';
  static const String notificacionRuta = 'Ruta permitida';
  static const String textoPorDefecto =
      'Entraste a un tramo prohibido. Sal de la vía y comunícate con operaciones';

  // Notificación fija mientras el viaje está en curso (servicio en primer plano).
  static const String viajeCanalNombre = 'Viaje en curso';
  static const String viajeCanalDescripcion =
      'Mantiene la conexión del viaje para poder avisarte de inmediato.';
  static const String viajeTitulo = 'Viaje en curso';
  static const String viajeTexto = 'Viasofia sigue atenta a tu ruta';

  // Permiso de notificaciones (Android 13 o superior): explicación antes de pedirlo.
  static const String permisoTitulo = 'Activar avisos';
  static const String permisoExplicacion =
      'Para avisarte al instante si entras a una ruta prohibida, aunque tengas la '
      'app minimizada o la pantalla bloqueada, necesitamos permiso para mostrar '
      'notificaciones.';
  static const String permisoContinuar = 'Continuar';
  static const String permisoAhoraNo = 'Ahora no';

  // Ahorro de batería del fabricante (se pide una sola vez).
  static const String bateriaTitulo = 'Mantener la conexión';
  static const String bateriaExplicacion =
      'Algunos teléfonos cierran las apps para ahorrar batería. Permite que Viasofia '
      'siga activa durante el viaje para que el aviso llegue a tiempo.';
  static const String bateriaPermitir = 'Permitir';
  static const String bateriaAhoraNo = 'Ahora no';
}

/// Textos del cierre de la sesión de la demostración.
class TextosSesionDemo {
  TextosSesionDemo._();

  /// Se muestra en la pantalla del código cuando la sesión terminó sin que el usuario la cerrara
  /// (vencida a las 6 h, simulación detenida o código nuevo).
  static const String sesionTerminada =
      'La sesión de la demostración terminó. Escribe el código nuevo para volver a enlazar.';
}
